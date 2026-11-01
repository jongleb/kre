type 'a queue = {
  name : string;
  codec : (module Kre_shared.Json.S with type t = 'a);
}

type handler =
  | Handler : 'a queue * ('a -> (unit, string) result Lwt.t) -> handler

let queue name codec = { name; codec }
let handle queue run = Handler (queue, run)

let table =
  Table.make ~name:"kre_jobs"
    [
      Table.column ~role:Primary_auto "id" Integer Not_null;
      Table.column "queue" (Text (Some 64)) Not_null;
      Table.column "payload" (Text None) Not_null;
      Table.column "status" (Text (Some 16)) Not_null;
      Table.column "attempts" Integer Not_null;
      Table.column ~role:Index "run_at" Double Not_null;
      Table.column "locked_until" Double Null;
      Table.column "last_error" (Text None) Null;
    ]

module type S = sig
  val enqueue : ?delay:float -> 'a queue -> 'a -> unit Lwt.t
  val register : handler -> unit
  val drain : unit -> int Lwt.t
  val on_start : unit -> unit Lwt.t
  val on_shutdown : unit -> unit Lwt.t
end

module Make
    (Db : Db.S)
    (Config : sig
      val poll : float
      val attempts : int
    end) =
struct
  let handlers : (string, handler) Hashtbl.t = Hashtbl.create 8
  let stop = ref (fun () -> Lwt.return_unit)
  let time seconds = Printf.sprintf "%.17g" seconds

  let register (Handler (queue, _) as handler) =
    Hashtbl.replace handlers queue.name handler

  let enqueue ?(delay = 0.) (type a) (queue : a queue) (payload : a) =
    let (module J) = queue.codec in
    Lwt.map ignore
      (Db.query
         "INSERT INTO kre_jobs (queue, payload, status, attempts, run_at) \
          VALUES (?, ?, 'queued', 0, ?)"
         [
           Some queue.name;
           Some (Jsonkit.to_string (J.to_json payload));
           Some (time (Unix.gettimeofday () +. delay));
         ])

  let claim () =
    let now = Unix.gettimeofday () in
    Db.transaction (fun _ ->
        Lwt.bind
          (Db.query
             "SELECT id, queue, payload, attempts FROM kre_jobs WHERE (status \
              = 'queued' AND run_at <= ?) OR (status = 'running' AND \
              locked_until < ?) ORDER BY run_at LIMIT 1 FOR UPDATE SKIP LOCKED"
             [ Some (time now); Some (time now) ])
          (function
            | [ [ Some id; Some queue; Some payload; Some attempts ] ] ->
                Lwt.map
                  (fun _ ->
                    Ok (Some (id, queue, payload, 1 + int_of_string attempts)))
                  (Db.query
                     "UPDATE kre_jobs SET status = 'running', locked_until = \
                      ?, attempts = attempts + 1 WHERE id = ?"
                     [ Some (time (now +. 300.)); Some id ])
            | _ -> Lwt.return_ok None))

  let perform queue payload =
    Option.fold
      ~none:(Lwt.return_error ("no handler for queue " ^ queue))
      ~some:(fun (Handler (queue, run)) ->
        Result.fold
          ~error:(fun errors ->
            Lwt.return_error
              (String.concat "; "
                 (List.map
                    (fun (error : Kre_shared.Validation.error) -> error.message)
                    (Kre_shared.Validation.to_list errors))))
          ~ok:(fun payload ->
            Lwt.catch
              (fun () -> run payload)
              (fun exn -> Lwt.return_error (Printexc.to_string exn)))
          (let (module J) = queue.codec in
           Kre_shared.Json.parse (module J) (Jsonkit.of_string payload)))
      (Hashtbl.find_opt handlers queue)

  let drain () =
    let rec loop done_ =
      Lwt.bind (claim ()) (function
        | Error () | Ok None -> Lwt.return done_
        | Ok (Some (id, queue, payload, attempts)) ->
            Lwt.bind
              (Lwt.bind (perform queue payload) (function
                | Ok () ->
                    Db.query "DELETE FROM kre_jobs WHERE id = ?" [ Some id ]
                | Error message when attempts >= Config.attempts ->
                    Db.query
                      "UPDATE kre_jobs SET status = 'dead', last_error = ?, \
                       locked_until = NULL WHERE id = ?"
                      [ Some message; Some id ]
                | Error message ->
                    Db.query
                      "UPDATE kre_jobs SET status = 'queued', last_error = ?, \
                       locked_until = NULL, run_at = ? WHERE id = ?"
                      [
                        Some message;
                        Some
                          (time
                             (Unix.gettimeofday ()
                             +. Float.pow 2. (float_of_int attempts)));
                        Some id;
                      ]))
              (fun _ -> loop (done_ + 1)))
    in
    loop 0

  let on_start () =
    let stopped, stopper = Lwt.wait () in
    let rec work () =
      match Lwt.state stopped with
      | Lwt.Return () | Lwt.Fail _ -> Lwt.return_unit
      | Lwt.Sleep ->
          Lwt.bind
            (Lwt.catch
               (fun () -> Lwt.map ignore (drain ()))
               (fun exn ->
                 Dream.error (fun log ->
                     log "jobs: %s" (Printexc.to_string exn));
                 Lwt.return_unit))
            (fun () ->
              Lwt.bind (Lwt.choose [ Lwt_unix.sleep Config.poll; stopped ]) work)
    in
    let worker = work () in
    (stop :=
       fun () ->
         Lwt.wakeup_later stopper ();
         worker);
    Lwt.return_unit

  let on_shutdown () = !stop ()
end

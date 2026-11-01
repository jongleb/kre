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
  val dashboard : Controller.t
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

  let dashboard =
    let local : unit Guard.t =
     fun request ->
      Lwt.map
        (function
          | Ok ("127.0.0.1" | "::1" | "localhost") -> Ok ()
          | Ok _ | Error _ ->
              Error (Error.forbidden "the jobs dashboard answers loopback only"))
        (Extract.ip request)
    in
    let rows () =
      Lwt.map
        (List.filter_map (function
          | [ Some id; Some queue; Some status; Some attempts; error ] ->
              Some (id, queue, status, attempts, Option.value error ~default:"")
          | _ -> None))
        (Db.query
           "SELECT id, queue, status, attempts, last_error FROM kre_jobs ORDER \
            BY id"
           [])
    in
    let page () =
      Lwt.bind (rows ()) (fun rows ->
          let counts =
            List.sort_uniq compare
              (List.map (fun (_, queue, status, _, _) -> (queue, status)) rows)
          in
          Dream.html
            (String.concat ""
               ([
                  "<!doctype html><meta charset=utf-8><title>Jobs</title>";
                  "<style>body{font:14px \
                   system-ui;margin:24px}td,th{padding:4px \
                   10px;text-align:left}form{display:inline}</style>";
                  "<h1>Jobs</h1><table><tr><th>queue</th><th>status</th><th>count</th></tr>";
                ]
               @ List.map
                   (fun (queue, status) ->
                     Printf.sprintf "<tr><td>%s</td><td>%s</td><td>%d</td></tr>"
                       (Dream.html_escape queue) status
                       (List.length
                          (List.filter
                             (fun (_, q, s, _, _) ->
                               String.equal q queue && String.equal s status)
                             rows)))
                   counts
               @ [ "</table><h2>Dead</h2><table>" ]
               @ List.filter_map
                   (fun (id, queue, status, attempts, error) ->
                     match status with
                     | "dead" ->
                         Some
                           (Printf.sprintf
                              "<tr><td>#%s</td><td>%s</td><td>%s \
                               attempts</td><td>%s</td><td><form method=post \
                               action=/__kre/jobs/%s/retry><button>retry</button></form> \
                               <form method=post \
                               action=/__kre/jobs/%s/delete><button>delete</button></form></td></tr>"
                              id (Dream.html_escape queue) attempts
                              (Dream.html_escape error) id id)
                     | _ -> None)
                   rows
               @ [ "</table>" ])))
    in
    let act verb sql parameters =
      Route.v `POST
        (Routes.( @--> )
           Routes.(s "__kre" / s "jobs" / str / s verb /? nil)
           (fun id ->
             Route.handle ~status:`See_Other ~guards:[ local ] Route.Raw
               (fun request ->
                 Lwt.bind
                   (Db.query sql (parameters id))
                   (fun _ ->
                     Lwt.map Result.ok (Dream.redirect request "/__kre/jobs")))))
    in
    Controller.v
      ~spec:{ Spec.prefix = "/__kre"; version = None; routes = [] }
      [
        Route.v `GET
          (Routes.( @--> )
             Routes.(s "__kre" / s "jobs" /? nil)
             (Route.handle ~status:`OK ~guards:[ local ] Route.Raw (fun _ ->
                  Lwt.map Result.ok (page ()))));
        Route.v `GET
          (Routes.( @--> )
             Routes.(s "__kre" / s "jobs.json" /? nil)
             (Route.handle ~status:`OK ~guards:[ local ] Route.Raw (fun _ ->
                  Lwt.bind (rows ()) (fun rows ->
                      Lwt.map Result.ok
                        (Dream.json
                           (Yojson.Basic.to_string
                              (`List
                                 (List.map
                                    (fun (id, queue, status, attempts, error) ->
                                      `Assoc
                                        [
                                          ("id", `String id);
                                          ("queue", `String queue);
                                          ("status", `String status);
                                          ("attempts", `String attempts);
                                          ("last_error", `String error);
                                        ])
                                    rows))))))));
        act "retry"
          "UPDATE kre_jobs SET status = 'queued', attempts = 0, run_at = ?, \
           locked_until = NULL WHERE id = ?" (fun id ->
            [ Some (time (Unix.gettimeofday ())); Some id ]);
        act "delete" "DELETE FROM kre_jobs WHERE id = ?" (fun id -> [ Some id ]);
      ]
end

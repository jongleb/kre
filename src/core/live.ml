type subscriber = { tables : string list; push : string option -> unit }

(** What a statement does to tables, read from its SQL. *)
type statement = Reads of string list | Writes of string list | Other

let subscribers : (int, subscriber) Hashtbl.t = Hashtbl.create 16
let next_id = ref 0
let reading : string list ref Lwt.key = Lwt.new_key ()
let pending : string list ref Lwt.key = Lwt.new_key ()

let publish tables =
  Hashtbl.iter
    (fun _ subscriber ->
      List.iter
        (fun table -> subscriber.push (Some table))
        (List.filter
           (fun table -> List.mem table subscriber.tables)
           (List.sort_uniq String.compare tables)))
    subscribers

let subscribe tables =
  let stream, push = Lwt_stream.create () in
  let id = !next_id in
  incr next_id;
  Hashtbl.replace subscribers id { tables; push };
  ( stream,
    fun () ->
      Hashtbl.remove subscribers id;
      push None )

let statement sql =
  let words =
    List.filter
      (fun word -> not (String.equal word ""))
      (String.split_on_char ' '
         (String.map
            (function
              | '(' | ')' | ',' | ';' | '\n' | '\t' | '\r' -> ' ' | c -> c)
            sql))
  in
  let skipped = [ "select"; "low_priority"; "ignore"; "into"; "from" ] in
  let rec names keywords found = function
    | keyword :: (next :: _ as rest)
      when List.mem (String.lowercase_ascii keyword) keywords
           && not (List.mem (String.lowercase_ascii next) skipped) ->
        let parts =
          String.split_on_char '.'
            (String.concat ""
               (String.split_on_char '"'
                  (String.concat "" (String.split_on_char '`' next))))
        in
        names keywords (List.nth parts (List.length parts - 1) :: found) rest
    | _ :: rest -> names keywords found rest
    | [] -> List.rev found
  in
  let first keywords =
    Writes (Option.to_list (List.nth_opt (names keywords [] words) 0))
  in
  match List.map String.lowercase_ascii words with
  | ("select" | "with") :: _ -> Reads (names [ "from"; "join" ] [] words)
  | ("insert" | "replace") :: _ -> first [ "into" ]
  | "update" :: _ -> first [ "update"; "low_priority"; "ignore" ]
  | "delete" :: _ -> first [ "from" ]
  | _ -> Other

let read sql =
  match statement sql with
  | Reads tables ->
      Option.iter (fun seen -> seen := tables @ !seen) (Lwt.get reading)
  | Writes _ | Other -> ()

let wrote sql =
  match (statement sql, Lwt.get pending) with
  | Writes tables, Some held -> held := tables @ !held
  | Writes tables, None -> publish tables
  | (Reads _ | Other), _ -> ()

let deferred run =
  let held = ref [] in
  Lwt.map
    (fun result ->
      Result.iter (fun _ -> publish !held) result;
      result)
    (Lwt.with_value pending (Some held) run)

let audit declared next request =
  let checked failure =
    let seen = ref [] in
    Lwt.bind
      (Lwt.with_value reading (Some seen) (fun () -> next request))
      (fun response ->
        match
          List.filter
            (fun table -> not (List.mem table declared))
            (List.sort_uniq String.compare !seen)
        with
        | [] -> Lwt.return response
        | missing ->
            let message =
              Printf.sprintf "%s reads %s; add it to [@@live]"
                (Dream.target request)
                (String.concat ", " missing)
            in
            failure message response)
  in
  match Sys.getenv_opt "KRE_ENV" with
  | Some "test" ->
      checked (fun message _ ->
          Error.to_response request (Error.internal message))
  | Some "dev" | None ->
      checked (fun message response ->
          Dream.warning (fun log -> log ~request "%s" message);
          Lwt.return response)
  | Some _ -> next request

let controller =
  Controller.v
    ~spec:{ Spec.prefix = "/__kre"; version = None; routes = [] }
    [
      Route.v `GET
        (Routes.( @--> )
           Routes.(s "__kre" / s "live" /? nil)
           (Route.handle ~status:`OK Route.Raw (fun request ->
                let changes, stop = subscribe (Dream.queries request "table") in
                Lwt.map Result.ok
                  (Dream.stream
                     ~headers:
                       [
                         ("Content-Type", "text/event-stream");
                         ("Cache-Control", "no-cache");
                       ]
                     (fun stream ->
                       Lwt.finalize
                         (fun () ->
                           Lwt.bind
                             (Lwt.bind (Dream.write stream ": live\n\n")
                                (fun () -> Dream.flush stream))
                             (fun () ->
                               Lwt_stream.iter_s
                                 (fun table ->
                                   Lwt.bind
                                     (Dream.write stream
                                        ("data: " ^ table ^ "\n\n"))
                                     (fun () -> Dream.flush stream))
                                 changes))
                         (fun () ->
                           stop ();
                           Lwt.return_unit))))));
    ]

type entry = {
  method_ : string;
  target : string;
  status : int;
  milliseconds : float;
  queries : string list;
}

(** Whether this process profiles: only under [FORGE_ENV=dev] or unset. *)
type mode = On | Off

let mode () =
  match Sys.getenv_opt "FORGE_ENV" with
  | None | Some "dev" -> On
  | Some _ -> Off

let log : string list ref Lwt.key = Lwt.new_key ()
let entries = ref []
let recent () = !entries

let sql text =
  Option.iter (fun queries -> queries := text :: !queries) (Lwt.get log)

let repeated entry =
  List.filter_map
    (fun query ->
      match List.length (List.filter (String.equal query) entry.queries) with
      | count when count >= 3 -> Some (query, count)
      | _ -> None)
    (List.sort_uniq String.compare entry.queries)

let middleware next request =
  match
    (mode (), String.starts_with ~prefix:"/__forge/" (Dream.target request))
  with
  | Off, _ | On, true -> next request
  | On, false ->
      let queries = ref [] in
      let started = Unix.gettimeofday () in
      Lwt.map
        (fun response ->
          entries :=
            List.filteri
              (fun index _ -> index < 50)
              ({
                 method_ = Dream.method_to_string (Dream.method_ request);
                 target = Dream.target request;
                 status = Dream.status_to_int (Dream.status response);
                 milliseconds = (Unix.gettimeofday () -. started) *. 1000.;
                 queries = List.rev !queries;
               }
              :: !entries);
          response)
        (Lwt.with_value log (Some queries) (fun () -> next request))

let controller =
  let page path respond =
    Route.v `GET
      (Routes.( @--> )
         Routes.(s "__forge" / s path /? nil)
         (Route.handle ~status:`OK Route.Raw (fun _ ->
              match mode () with
              | Off ->
                  Lwt.return_error
                    (Error.not_found "the profiler runs in dev only")
              | On -> Lwt.map Result.ok (respond ()))))
  in
  Controller.v
    ~spec:{ Spec.prefix = "/__forge"; version = None; routes = [] }
    [
      page "profiler.json" (fun () ->
          Dream.json
            (Yojson.Basic.to_string
               (`List
                  (List.map
                     (fun entry ->
                       `Assoc
                         [
                           ("method", `String entry.method_);
                           ("target", `String entry.target);
                           ("status", `Int entry.status);
                           ("milliseconds", `Float entry.milliseconds);
                           ( "queries",
                             `List
                               (List.map
                                  (fun query -> `String query)
                                  entry.queries) );
                           ( "repeated",
                             `List
                               (List.map
                                  (fun (query, count) ->
                                    `Assoc
                                      [
                                        ("query", `String query);
                                        ("count", `Int count);
                                      ])
                                  (repeated entry)) );
                         ])
                     (recent ())))));
      page "profiler" (fun () ->
          Dream.html
            (String.concat ""
               ([
                  "<!doctype html><meta charset=utf-8><title>Forge \
                   profiler</title>";
                  "<style>body{font:14px system-ui;margin:24px}td{padding:4px \
                   8px;vertical-align:top}.n1{color:#b00}code{font-size:12px}</style>";
                  "<h1>Requests</h1><table><tr><th>request</th><th>status</th><th>ms</th><th>SQL</th></tr>";
                ]
               @ List.map
                   (fun entry ->
                     Printf.sprintf
                       "<tr><td>%s \
                        %s</td><td>%d</td><td>%.1f</td><td>%s%s</td></tr>"
                       entry.method_
                       (Dream.html_escape entry.target)
                       entry.status entry.milliseconds
                       (String.concat ""
                          (List.map
                             (fun query ->
                               "<div><code>" ^ Dream.html_escape query
                               ^ "</code></div>")
                             entry.queries))
                       (String.concat ""
                          (List.map
                             (fun (query, count) ->
                               Printf.sprintf
                                 "<div class=n1>N+1: %d × <code>%s</code></div>"
                                 count (Dream.html_escape query))
                             (repeated entry))))
                   (recent ())
               @ [ "</table>" ])));
    ]

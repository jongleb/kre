type check = { name : string; run : unit -> (unit, string) result Lwt.t }
type bean = { name : string; needs : string list }
type access = Loopback | Anyone

let mermaid beans =
  String.concat "\n"
    ("graph TD"
     :: List.concat_map
          (fun bean ->
            match bean.needs with
            | [] -> [ "  " ^ bean.name ]
            | needs ->
                List.map
                  (fun needed -> Printf.sprintf "  %s --> %s" bean.name needed)
                  needs)
          beans
    @ [ "" ])

type t = { controller : Controller.t; metrics : Dream.middleware }

let make ?(checks = []) ?(info = []) ?(env = []) ?(beans = [])
    ?(access = Loopback) controllers =
  let requests : (string * int, int) Hashtbl.t = Hashtbl.create 16 in
  let seconds : (string, float) Hashtbl.t = Hashtbl.create 16 in
  let metrics : Dream.middleware =
   fun next request ->
    let started = Unix.gettimeofday () in
    Lwt.map
      (fun response ->
        let method_ = Dream.method_to_string (Dream.method_ request) in
        let status = Dream.status_to_int (Dream.status response) in
        Hashtbl.replace requests (method_, status)
          (1
          + Option.value
              (Hashtbl.find_opt requests (method_, status))
              ~default:0);
        Hashtbl.replace seconds method_
          (Unix.gettimeofday () -. started
          +. Option.value (Hashtbl.find_opt seconds method_) ~default:0.);
        response)
      (next request)
  in
  let allowed : unit Guard.t =
   fun request ->
    Lwt.map
      (fun ip ->
        match (access, ip) with
        | Anyone, _ -> Ok ()
        | Loopback, Ok ("127.0.0.1" | "::1" | "localhost") -> Ok ()
        | Loopback, _ ->
            Error (Error.forbidden "the actuator answers loopback only"))
      (Extract.ip request)
  in
  let pairs fields =
    `Assoc (List.map (fun (key, value) -> (key, `String value)) fields)
  in
  let json value = Dream.json (Yojson.Basic.to_string value) in
  let route path respond =
    Route.v `GET
      (Routes.( @--> )
         Routes.(s "actuator" / s path /? nil)
         (Route.handle ~status:`OK ~guards:[ allowed ] Route.Raw (fun _ ->
              Lwt.map Result.ok (respond ()))))
  in
  let specs () =
    List.map (fun (controller : Controller.t) -> controller.spec) controllers
  in
  let routes =
    [
      route "health" (fun () ->
          Lwt.bind
            (Lwt_list.map_p
               (fun (check : check) ->
                 Lwt.map (fun outcome -> (check.name, outcome)) (check.run ()))
               checks)
            (fun outcomes ->
              let state =
                Option.fold ~none:`Up
                  ~some:(fun _ -> `Down)
                  (List.find_opt
                     (fun (_, outcome) -> Result.is_error outcome)
                     outcomes)
              in
              Dream.json
                ~status:
                  (match state with
                  | `Up -> `OK
                  | `Down -> `Service_Unavailable)
                (Yojson.Basic.to_string
                   (`Assoc
                      [
                        ( "status",
                          `String
                            (match state with `Up -> "up" | `Down -> "down") );
                        ( "checks",
                          `Assoc
                            (List.map
                               (fun (name, outcome) ->
                                 ( name,
                                   `String
                                     (Result.fold
                                        ~ok:(fun () -> "up")
                                        ~error:(fun message ->
                                          "down: " ^ message)
                                        outcome) ))
                               outcomes) );
                      ]))));
      route "info" (fun () -> json (pairs info));
      route "env" (fun () -> json (pairs env));
      route "beans" (fun () ->
          json
            (`List
               (List.map
                  (fun bean ->
                    `Assoc
                      [
                        ("name", `String bean.name);
                        ( "needs",
                          `List (List.map (fun name -> `String name) bean.needs)
                        );
                      ])
                  beans)));
      route "beans.mmd" (fun () ->
          Dream.respond
            ~headers:[ ("Content-Type", "text/plain; charset=utf-8") ]
            (mermaid beans));
      route "routes" (fun () -> json (`List (List.map Spec.to_json (specs ()))));
      route "openapi.json" (fun () ->
          json (Openapi.document ~title:"API" ~version:"0.0.0" (specs ())));
      route "metrics" (fun () ->
          let gc = Gc.quick_stat () in
          Dream.respond
            ~headers:[ ("Content-Type", "text/plain; version=0.0.4") ]
            (String.concat "\n"
               (Hashtbl.fold
                  (fun (method_, status) count lines ->
                    Printf.sprintf
                      "forge_requests_total{method=\"%s\",status=\"%d\"} %d"
                      method_ status count
                    :: lines)
                  requests []
               @ Hashtbl.fold
                   (fun method_ total lines ->
                     Printf.sprintf
                       "forge_request_seconds_sum{method=\"%s\"} %f" method_
                       total
                     :: lines)
                   seconds []
               @ [
                   Printf.sprintf "ocaml_gc_heap_words %d" gc.heap_words;
                   Printf.sprintf "ocaml_gc_major_collections %d"
                     gc.major_collections;
                   "";
                 ])));
    ]
  in
  {
    controller =
      Controller.v
        ~spec:{ Spec.prefix = "/actuator"; version = None; routes = [] }
        routes;
    metrics;
  }

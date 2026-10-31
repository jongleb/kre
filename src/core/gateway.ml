type socket = { id : int; send : string -> unit Lwt.t; peers : socket list ref }

type handler = {
  event : string;
  run : socket -> Jsonkit.t -> (Jsonkit.t option, Error.t) result Lwt.t;
}

type t = { handlers : handler list; clients : socket list ref; next : int ref }

let frame ~event data =
  Jsonkit.to_string (`Assoc [ ("event", `String event); ("data", data) ])

let decode (module J : Forge_shared.Json.S) data =
  Result.map_error Error.unprocessable (Forge_shared.Json.parse (module J) data)

let on event (module J : Forge_shared.Json.S) (module R : Forge_shared.Json.S)
    run =
  {
    event;
    run =
      (fun socket data ->
        match decode (module J) data with
        | Error error -> Lwt.return_error error
        | Ok body ->
            Lwt_result.map
              (fun reply -> Some (R.to_json reply))
              (run socket body));
  }

let notify event (module J : Forge_shared.Json.S) run =
  {
    event;
    run =
      (fun socket data ->
        match decode (module J) data with
        | Error error -> Lwt.return_error error
        | Ok body -> Lwt_result.map (fun () -> None) (run socket body));
  }

let send socket ~event (module R : Forge_shared.Json.S) value =
  socket.send (frame ~event (R.to_json value))

let broadcast socket ~event (module R : Forge_shared.Json.S) value =
  Lwt_list.iter_p
    (fun peer -> peer.send (frame ~event (R.to_json value)))
    !(socket.peers)

let make handlers = { handlers; clients = ref []; next = ref 0 }

let connect gateway ~send =
  incr gateway.next;
  let socket = { id = !(gateway.next); send; peers = gateway.clients } in
  gateway.clients := socket :: !(gateway.clients);
  let fail error =
    send (frame ~event:"error" (Error.to_json ~instance:"ws" error))
  in
  let receive text =
    match Yojson.Basic.from_string text with
    | `Assoc fields -> (
        match (List.assoc_opt "event" fields, List.assoc_opt "data" fields) with
        | Some (`String event), data -> (
            match
              List.find_opt
                (fun handler -> String.equal handler.event event)
                gateway.handlers
            with
            | None -> fail (Error.not_found ("no handler for event " ^ event))
            | Some handler ->
                Lwt.bind
                  (Lwt.catch
                     (fun () ->
                       handler.run socket (Option.value data ~default:`Null))
                     (fun exn ->
                       Lwt.return_error
                         (Error.internal
                            ("handler failed: " ^ Printexc.to_string exn))))
                  (function
                    | Ok (Some reply) -> send (frame ~event reply)
                    | Ok None -> Lwt.return_unit
                    | Error error -> fail error))
        | _ -> fail (Error.bad_request "a frame is {\"event\": …, \"data\": …}")
        )
    | _ | (exception Yojson.Json_error _) ->
        fail (Error.bad_request "a frame is {\"event\": …, \"data\": …}")
  in
  let disconnect () =
    gateway.clients :=
      List.filter (fun client -> client.id <> socket.id) !(gateway.clients)
  in
  (receive, disconnect)

let controller ~path gateway =
  Controller.v
    ~spec:{ Spec.prefix = "/" ^ path; version = None; routes = [] }
    [
      Route.v `GET
        (Routes.( @--> )
           (List.fold_right
              (fun segment rest -> Routes.( / ) (Routes.s segment) rest)
              (List.filter
                 (fun segment -> segment <> "")
                 (String.split_on_char '/' path))
              Fun.id Routes.nil)
           (Route.handle ~status:`OK Route.Raw (fun _ ->
                Lwt.map Result.ok
                  (Dream.websocket (fun websocket ->
                       let receive, disconnect =
                         connect gateway ~send:(fun text ->
                             Dream.send websocket text)
                       in
                       let rec loop () =
                         Lwt.bind (Dream.receive websocket) (function
                           | Some text -> Lwt.bind (receive text) loop
                           | None ->
                               disconnect ();
                               Dream.close_websocket websocket)
                       in
                       loop ())))));
    ]

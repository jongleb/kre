type tls =
  | Development_certificate
  | Certificate of { certificate_file : string; key_file : string }

type error_handler = Dream.request -> Error.t -> Dream.response Lwt.t

let handler ?(middleware = []) ?(error_handler = Error.to_response) controllers
    =
  let routes =
    List.concat_map
      (fun (controller : Controller.t) ->
        List.map
          (fun (route : Route.t) ->
            ( route.verb,
              Routes.map
                (fun (handle : Route.handler) ->
                  Dream.pipeline (controller.middleware @ route.middleware)
                    (fun request ->
                      Lwt.bind (handle request)
                        (Result.fold ~ok:Lwt.return
                           ~error:(error_handler request))))
                route.target ))
          controller.routes)
      controllers
  in
  let router verb =
    Routes.one_of
      (List.filter_map
         (fun (route_verb, target) ->
           if route_verb = verb then Some target else None)
         routes)
  in
  let get = router `GET
  and post = router `POST
  and put = router `PUT
  and patch = router `PATCH
  and delete = router `DELETE in
  Dream.pipeline middleware (fun request ->
      let path, query = Dream.split_target (Dream.target request) in
      let matched =
        Option.map
          (fun router -> Routes.match' router ~target:path)
          (match Dream.method_ request with
          | `GET -> Some get
          | `POST -> Some post
          | `PUT -> Some put
          | `PATCH -> Some patch
          | `DELETE -> Some delete
          | _ -> None)
      in
      match matched with
      | Some (Routes.FullMatch handle) -> handle request
      | Some (Routes.MatchWithTrailingSlash _) ->
          Dream.redirect ~status:`Moved_Permanently request
            (String.sub path 0 (String.length path - 1)
            ^ if query = "" then "" else "?" ^ query)
      | Some Routes.NoMatch | None ->
          error_handler request
            (Error.not_found
               (Printf.sprintf "no route for %s %s"
                  (Dream.method_to_string (Dream.method_ request))
                  path)))

let run ?interface ?port ?tls ?middleware ?error_handler
    ?(on_start = Lwt.return) ?(on_shutdown = Lwt.return) controllers =
  let stop, stopper = Lwt.wait () in
  List.iter
    (fun signal ->
      ignore
        (Lwt_unix.on_signal signal (fun _ ->
             match Lwt.state stop with
             | Lwt.Sleep -> Lwt.wakeup_later stopper ()
             | Lwt.Return () | Lwt.Fail _ -> ())))
    [ Sys.sigint; Sys.sigterm ];
  let tls, certificate_file, key_file =
    match tls with
    | None -> (None, None, None)
    | Some Development_certificate -> (Some true, None, None)
    | Some (Certificate { certificate_file; key_file }) ->
        (Some true, Some certificate_file, Some key_file)
  in
  Lwt_main.run
    (let open Lwt.Syntax in
     let* () = on_start () in
     let* () =
       Dream.serve ?interface ?port ~stop ?tls ?certificate_file ?key_file
         (handler ?middleware ?error_handler controllers)
     in
     on_shutdown ())

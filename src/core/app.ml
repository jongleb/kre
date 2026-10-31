type tls =
  | Development_certificate
  | Certificate of { certificate_file : string; key_file : string }

let handler ?(middleware = []) ?(error_handler = Error.to_response) controllers
    =
  let route controller (route : Route.t) =
    ( (route.verb, route.matching),
      Routes.map
        (fun (handle : Route.handler) ->
          Dream.pipeline (controller.Controller.middleware @ route.middleware)
            (fun request ->
              Lwt.bind (handle request)
                (Result.fold ~ok:Lwt.return
                   ~error:
                     (Option.value route.error_handler
                        ~default:
                          (Option.value controller.error_handler
                             ~default:error_handler)
                        request))))
        route.target )
  in
  let routers controllers =
    let routes =
      List.concat_map
        (fun (controller : Controller.t) ->
          List.map (route controller) controller.routes)
        controllers
    in
    let tries =
      List.concat_map
        (fun verb ->
          List.map
            (fun matching ->
              ( (verb, matching),
                Routes.one_of
                  (List.filter_map
                     (fun (key, target) ->
                       if key = (verb, matching) then Some target else None)
                     routes) ))
            [ Route.Exact; Route.Rest ])
        [ `GET; `POST; `PUT; `PATCH; `DELETE; `HEAD; `OPTIONS ]
    in
    let trie key = List.assoc key tries in
    fun verb target ->
      match Routes.match' (trie (verb, Route.Exact)) ~target with
      | Routes.NoMatch -> Routes.match' (trie (verb, Route.Rest)) ~target
      | matched -> matched
  in
  let hosts =
    List.sort_uniq compare
      (List.filter_map
         (fun (controller : Controller.t) -> controller.host)
         controllers)
  in
  let groups =
    List.map
      (fun host ->
        ( Some host,
          routers
            (List.filter
               (fun (controller : Controller.t) -> controller.host = Some host)
               controllers) ))
      hosts
    @ [
        ( None,
          routers
            (List.filter
               (fun (controller : Controller.t) -> controller.host = None)
               controllers) );
      ]
  in
  Dream.pipeline middleware (fun request ->
      let path, query = Dream.split_target (Dream.target request) in
      let host = Option.value (Dream.header request "Host") ~default:"" in
      let attempt verb =
        List.find_map
          (fun (pattern, routers) ->
            match
              ( Option.map (fun pattern -> Host.parameters ~pattern host) pattern,
                routers verb path )
            with
            | ( (None | Some (Some _)),
                ((Routes.FullMatch _ | Routes.MatchWithTrailingSlash _) as
                 matched) ) ->
                Some matched
            | _ -> None)
          groups
      in
      let verb =
        match Dream.method_ request with
        | #Spec.verb as verb -> Some verb
        | _ -> None
      in
      let matched =
        match (verb, Option.bind verb attempt) with
        | Some `HEAD, None ->
            Option.map
              (function
                | Routes.FullMatch handle ->
                    Routes.FullMatch
                      (fun request ->
                        Lwt.map
                          (fun response ->
                            Dream.set_body response "";
                            response)
                          (handle request))
                | other -> other)
              (attempt `GET)
        | _, matched -> matched
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
  let specs =
    List.map (fun (controller : Controller.t) -> controller.spec) controllers
  in
  let write file json =
    Out_channel.with_open_text file (fun channel ->
        Out_channel.output_string channel (Yojson.Basic.pretty_to_string json))
  in
  match Array.to_list Sys.argv with
  | _ :: "--emit-spec" :: file :: _ ->
      write file (`List (List.map Spec.to_json specs))
  | _ :: "--emit-openapi" :: file :: _ ->
      write file
        (Openapi.document
           ~title:
             (Filename.remove_extension (Filename.basename Sys.executable_name))
           ~version:"0.0.0" specs)
  | _ ->
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

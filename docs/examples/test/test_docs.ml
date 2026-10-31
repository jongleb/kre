let call ?(headers = []) handler method_ target =
  let response =
    Dream.test handler (Dream.request ~method_ ~target ~headers "")
  in
  ( Dream.status_to_int (Dream.status response),
    Lwt_main.run (Dream.body response) )

let app controllers = Forge.App.handler controllers

let () =
  Alcotest.run "docs"
    [
      ( "examples",
        [
          Alcotest.test_case "guards: controller-wide, then evidence" `Quick
            (fun () ->
              let admin =
                app [ Admin_controller.register (module Fake_cats) ]
              in
              Alcotest.(check (list int))
                "statuses" [ 401; 403; 204 ]
                (List.map
                   (fun headers ->
                     fst (call ~headers admin `DELETE "/admin/cats"))
                   [
                     [];
                     [ ("X-User", "ann") ];
                     [ ("X-User", "ann"); ("X-Role", "admin") ];
                   ]));
          Alcotest.test_case "custom decorators" `Quick (fun () ->
              Alcotest.(check (pair int string))
                "whoami" (200, "127.0.0.1:0 fr")
                (call
                   ~headers:[ ("Accept-Language", "fr") ]
                   (app [ Whoami_controller.register () ])
                   `GET "/whoami"));
          Alcotest.test_case "request scope" `Quick (fun () ->
              let trace = app [ Trace_controller.register () ] in
              let first = call trace `GET "/trace" in
              let second = call trace `GET "/trace" in
              Alcotest.(check (list string))
                "ids"
                [ "request 1"; "request 2" ]
                [ snd first; snd second ]);
          Alcotest.test_case "exception filter" `Quick (fun () ->
              Alcotest.(check (pair int string))
                "page"
                (404, "<h1>Nothing here</h1>")
                (call
                   (Forge.App.handler ~error_handler:Error_pages.handler [])
                   `GET "/missing"));
          Alcotest.test_case "redirect, timeout, header, controller filter"
            `Quick (fun () ->
              let legacy = app [ Legacy_controller.register () ] in
              let header target name =
                Dream.header (Dream.test legacy (Dream.request ~target "")) name
              in
              Alcotest.(check (list (pair int string)))
                "responses"
                [
                  (302, "");
                  (504, "");
                  (200, "fresh");
                  (404, "<h1>Nothing here</h1>");
                ]
                (List.map
                   (fun target ->
                     match call legacy `GET target with
                     | 504, _ -> (504, "")
                     | response -> response)
                   [
                     "/legacy/cats";
                     "/legacy/slow";
                     "/legacy/fresh";
                     "/legacy/gone";
                   ]);
              Alcotest.(check (pair (option string) (option string)))
                "headers"
                (Some "/cats", Some "no-store")
                ( header "/legacy/cats" "Location",
                  header "/legacy/fresh" "Cache-Control" ));
          Alcotest.test_case "[@@authorize] sees typed arguments" `Quick
            (fun () ->
              let notes = app [ Notes_controller.register () ] in
              Alcotest.(check (list (pair int string)))
                "responses"
                [ (200, "note 1 for ann"); (403, ""); (401, "") ]
                (List.map
                   (fun (headers, target) ->
                     match call ~headers notes `GET target with
                     | ((403 | 401) as status), _ -> (status, "")
                     | response -> response)
                   [
                     ([ ("X-User", "ann") ], "/notes/1");
                     ([ ("X-User", "ann") ], "/notes/2");
                     ([], "/notes/1");
                   ]));
          Alcotest.test_case "jwt login, then a role" `Quick (fun () ->
              let session = app [ Session_controller.register () ] in
              let token =
                snd
                  ( Dream.test session
                      (Dream.request ~method_:`POST ~target:"/session/login"
                         {|{"user":"root","password":"secret"}|})
                  |> fun response ->
                    (response, Lwt_main.run (Dream.body response)) )
              in
              let reset headers =
                fst (call ~headers session `POST "/session/reset")
              in
              Alcotest.(check (list int))
                "statuses" [ 204; 401 ]
                [ reset [ ("Authorization", "Bearer " ^ token) ]; reset [] ]);
          Alcotest.test_case "server-sent events" `Quick (fun () ->
              let response =
                Dream.test
                  (app [ Ticks_controller.register () ])
                  (Dream.request ~target:"/ticks?upto=3" "")
              in
              Alcotest.(check (pair (option string) string))
                "stream"
                ( Some "text/event-stream",
                  "data: {\"n\":0}\n\ndata: {\"n\":1}\n\ndata: {\"n\":2}\n\n" )
                ( Dream.header response "Content-Type",
                  Lwt_main.run (Dream.body response) ));
          Alcotest.test_case "fake provider" `Quick (fun () ->
              Alcotest.(check int)
                "found" 200
                (fst
                   (call
                      (app (Composition.controllers ~fake:`Fake))
                      `GET "/cats/1")));
        ] );
    ]

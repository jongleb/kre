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
          Alcotest.test_case "fake provider" `Quick (fun () ->
              Alcotest.(check int)
                "found" 200
                (fst
                   (call
                      (app (Composition.controllers ~fake:`Fake))
                      `GET "/cats/1")));
        ] );
    ]

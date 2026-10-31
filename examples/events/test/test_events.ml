let () =
  let app = [%wire] in
  let handler = Dream.test (Forge.App.handler app.controllers) in
  let call method_ target body =
    let response = handler (Dream.request ~method_ ~target body) in
    ( Dream.status_to_int (Dream.status response),
      Lwt_main.run (Dream.body response) )
  in
  Alcotest.run "events"
    [
      ( "on_event",
        [
          Alcotest.test_case "publish reaches the listener" `Quick (fun () ->
              let signed_up = call `POST "/signup" {|{"email":"ann@x.io"}|} in
              Alcotest.(check (list (pair int string)))
                "responses"
                [ (204, ""); (200, {|["welcome ann@x.io"]|}) ]
                [ signed_up; call `GET "/signup/outbox" "" ]);
        ] );
    ]

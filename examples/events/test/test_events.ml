let () =
  let app = [%wire] in
  let actuator = Forge.Actuator.make ~checks:app.health app.controllers in
  let handler =
    Dream.test
      (Forge.App.handler ~middleware:[ actuator.metrics ]
         (actuator.controller :: app.controllers))
  in
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
          Alcotest.test_case "interval jobs run between start and shutdown"
            `Quick (fun () ->
              let count () =
                int_of_string (snd (call `GET "/signup/digests" ""))
              in
              Lwt_main.run
                (let open Lwt.Syntax in
                 let* () = app.on_start () in
                 let* () = Lwt_unix.sleep 0.1 in
                 app.on_shutdown ());
              let ran = count () in
              Lwt_main.run (Lwt_unix.sleep 0.1);
              Alcotest.(check (pair bool int))
                "ran a few times, then stopped" (true, ran)
                (ran >= 2, count ()));
          Alcotest.test_case "actuator" `Quick (fun () ->
              let health = call `GET "/actuator/health" "" in
              let metrics = snd (call `GET "/actuator/metrics" "") in
              let routes = snd (call `GET "/actuator/routes" "") in
              Alcotest.(check (list string))
                "answers"
                [ {|{"status":"up","checks":{"mailer":"up"}}|}; "true"; "true" ]
                [
                  snd health;
                  string_of_bool
                    (List.exists
                       (String.starts_with ~prefix:"forge_requests_total")
                       (String.split_on_char '\n' metrics));
                  string_of_bool
                    (Yojson.Basic.Util.(
                       List.length (to_list (Yojson.Basic.from_string routes)))
                    = 1);
                ]);
        ] );
    ]

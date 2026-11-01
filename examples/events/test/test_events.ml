let () =
  let app = [%wire] in
  let actuator =
    Kre.Actuator.make ~checks:app.health ~beans:app.beans app.controllers
  in
  let handler =
    Dream.test
      (Kre.App.handler ~middleware:[ actuator.metrics ]
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
                       (String.starts_with ~prefix:"kre_requests_total")
                       (String.split_on_char '\n' metrics));
                  string_of_bool
                    (Yojson.Basic.Util.(
                       List.length (to_list (Yojson.Basic.from_string routes)))
                    = 1);
                ]);
          Alcotest.test_case "every notifier, wrapped by the decorator" `Quick
            (fun () ->
              Alcotest.(check (pair int string))
                "notify"
                (200, {|["email ann@x.io","push ann@x.io","audit ann@x.io"]|})
                (call `GET "/signup/notify" ""));
          Alcotest.test_case "KRE_ENV picks the profile provider" `Quick
            (fun () ->
              let greet (wiring : Kre.Wiring.t) =
                Lwt_main.run
                  (Dream.body
                     (Dream.test
                        (Kre.App.handler wiring.controllers)
                        (Dream.request ~target:"/signup/greet" "")))
              in
              let default = greet app in
              Unix.putenv "KRE_ENV" "quiet";
              let quiet = greet [%wire] in
              Unix.putenv "KRE_ENV" "dev";
              Alcotest.(check (pair string string))
                "greetings" ("hello ann", "psst ann") (default, quiet));
          Alcotest.test_case "beans: the wired graph" `Quick (fun () ->
              Alcotest.(check (pair int string))
                "mermaid"
                ( 200,
                  "graph TD\n\
                  \  Email_notifier\n\
                  \  Push_notifier\n\
                  \  Notifications --> Email_notifier\n\
                  \  Notifications --> Push_notifier\n\
                  \  Audited_notifications --> Notifications\n\
                  \  Bus\n\
                  \  Greeting\n\
                  \  Mailer\n\
                  \  Signup_controller --> Bus\n\
                  \  Signup_controller --> Mailer\n\
                  \  Signup_controller --> Audited_notifications\n\
                  \  Signup_controller --> Greeting\n" )
                (call `GET "/actuator/beans.mmd" ""));
        ] );
    ]

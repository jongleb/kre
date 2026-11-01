let port = 19000 + (Unix.getpid () mod 1000)

let () =
  let stop, stopper = Lwt.wait () in
  let output =
    Lwt_main.run
      (let server =
         Dream.serve ~interface:"127.0.0.1" ~port ~stop
           (Kre.App.handler
              [
                Kre.Live.controller;
                Cats_controller.register (module Cats_service);
              ])
       in
       let%lwt () = Lwt_unix.sleep 0.2 in
       let%lwt output =
         Lwt_process.pread
           ( "",
             [|
               Option.value (Sys.getenv_opt "NODE") ~default:"node";
               "--experimental-eventsource";
               "--no-warnings";
               "js/examples/cats/client_js/scenario.js";
               string_of_int port;
             |] )
       in
       Lwt.wakeup_later stopper ();
       let%lwt () = server in
       Lwt.return output)
  in
  let router =
    Lwt_main.run
      (Lwt_process.pread
         ( "",
           [|
             Option.value (Sys.getenv_opt "NODE") ~default:"node";
             "js/examples/cats/client_js/router_check.js";
           |] ))
  in
  Alcotest.run "melange client"
    [
      ( "node",
        [
          Alcotest.test_case "router" `Quick (fun () ->
              Alcotest.(check string)
                "transcript"
                "href /cats/42\n\
                 href /cats?limit=5&breed=maine%20coon\n\
                 match 7\n\
                 match none\n\
                 search 20/persian\n\
                 search limit:type\n\
                 link <a href=\"/cats/3\">tom</a>\n\
                 view loading\n\
                 view Not found\n"
                router);
          Alcotest.test_case "scenario" `Quick (fun () ->
              Alcotest.(check string)
                "transcript"
                "ok tom\n\
                 problem 422 urn:kre:error:validation note:max_length\n\
                 ok 1\n\
                 problem 404 urn:kre:error:not_found \n\
                 live cats\n"
                output);
        ] );
    ]

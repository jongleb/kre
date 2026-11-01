let port = 20000 + (Unix.getpid () mod 1000)

let rec ready attempts =
  let socket = Lwt_unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  let%lwt connected =
    Lwt.catch
      (fun () ->
        Lwt.map Result.ok
          (Lwt_unix.connect socket
             (Unix.ADDR_INET (Unix.inet_addr_loopback, port))))
      Lwt.return_error
  in
  let%lwt () = Lwt_unix.close socket in
  match (connected, attempts) with
  | Ok (), _ -> Lwt.return_unit
  | Error exn, 0 -> Lwt.fail exn
  | Error _, _ ->
      let%lwt () = Lwt_unix.sleep 0.1 in
      ready (attempts - 1)

let () =
  let database_url = Sys.getenv "DATABASE_URL" in
  let output =
    Lwt_main.run
      (let server =
         Lwt_process.open_process_none ~stdout:`Dev_null ~stderr:`Dev_null
           ("", [| "../bin/main.exe" |])
           ~env:
             (Array.append
                [| Printf.sprintf "PORT=%d" port |]
                (Unix.environment ()))
       in
       let%lwt () = ready 100 in
       let%lwt conn = Kre_db_mariadb.Driver.connect database_url in
       let%lwt () =
         Lwt_list.iter_s
           (fun table ->
             Kre_db_mariadb.Driver.execute conn ("DELETE FROM " ^ table))
           [ "kre_jobs"; "adoptions"; "credentials"; "cats"; "users" ]
       in
       let%lwt () = Kre_db_mariadb.Driver.close conn in
       let%lwt output =
         Lwt_process.pread
           ( "",
             [|
               Option.value (Sys.getenv_opt "NODE") ~default:"node";
               "--experimental-eventsource";
               "--no-warnings";
               "../client/js/examples/shelter/client/scenario.js";
               string_of_int port;
             |] )
       in
       server#terminate;
       let%lwt _ = server#close in
       Lwt.return output)
  in
  Alcotest.run "shelter in node"
    [
      ( "scenario",
        [
          Alcotest.test_case "typed clients, live loaders, router" `Quick
            (fun () ->
              Alcotest.(check string)
                "transcript"
                "boss ok admin\n\
                 ann ok member\n\
                 ann admits problem 403 urn:kre:error:forbidden\n\
                 ann adopts ok tom\n\
                 again problem 409 urn:kre:error:conflict\n\
                 available ok felix\n\
                 live cats\n\
                 login <form><input type=\"email\" value=\"\"/><input \
                 type=\"password\" value=\"\"/><button type=\"submit\">Log \
                 in</button></form>\n"
                output);
        ] );
    ]

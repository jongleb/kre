let url =
  match Sys.getenv_opt "FORGE_TEST_DB_URL" with
  | Some url -> url
  | None ->
      prerr_endline
        "set FORGE_TEST_DB_URL, e.g. \
         mariadb://forge:forge@127.0.0.1:3399/forge_test";
      exit 2

module Db =
  Forge.Db.Make
    (Forge_db_mariadb.Driver)
    (struct
      let url = url
      let size = 2
    end)

module Cats = Cats_db_service.Make (Db)

let app =
  Dream.test (Forge.App.handler [ Cats_controller.register (module Cats) ])

let call ?(headers = []) ?(body = "") method_ target =
  let response = app (Dream.request ~method_ ~target ~headers body) in
  ( Dream.status_to_int (Dream.status response),
    Lwt_main.run (Dream.body response) )

let () =
  Lwt_main.run (Cats.reset ());
  Alcotest.run "cats on mariadb"
    [
      ( "sqlgg",
        [
          Alcotest.test_case "insert through the controller" `Quick (fun () ->
              Alcotest.(check (pair int string))
                "created"
                (201, {|{"id":1,"name":"tom","age":3,"breed":"siamese"}|})
                (call
                   ~headers:[ ("X-User", "ann") ]
                   ~body:{|{"name":"tom","age":3,"breed":"siamese"}|} `POST
                   "/cats"));
          Alcotest.test_case "read back from the database" `Quick (fun () ->
              Alcotest.(check (list (pair int string)))
                "rows"
                [
                  (200, {|{"id":1,"name":"tom","age":3,"breed":"siamese"}|});
                  (200, {|[{"id":1,"name":"tom","age":3,"breed":"siamese"}]|});
                  (404, "");
                ]
                (List.map
                   (fun (status, body) ->
                     (status, match status with 404 -> "" | _ -> body))
                   [
                     call `GET "/cats/1"; call `GET "/cats"; call `GET "/cats/2";
                   ]));
          Alcotest.test_case "transaction rolls back on Error" `Quick (fun () ->
              let attempt =
                Lwt_main.run
                  (Db.transaction (fun conn ->
                       let module Sql = Cats_sql.Make (Forge_db_mariadb.Sql) in
                       let%lwt _ =
                         Sql.insert conn ~name:"ghost" ~age:1L ~breed:"persian"
                       in
                       Lwt.return_error "abort"))
              in
              Alcotest.(check (pair (result reject string) int))
                "rolled back" (Error "abort", 1)
                ( Result.map ignore attempt,
                  List.length (Lwt_main.run (Cats.find_all ())) ));
        ] );
    ]

# Async providers and dynamic modules

Nest: `forRoot(config)` and async factories. Kre: a functor with a config module. This is how the database pool is built:

<!-- $MDX file=../examples/cats/db/test/test_db.ml -->
```ocaml
let url =
  match Sys.getenv_opt "KRE_TEST_DB_URL" with
  | Some url -> url
  | None ->
      prerr_endline
        "set KRE_TEST_DB_URL, e.g. mariadb://kre:kre@127.0.0.1:3399/kre_test";
      exit 2

module Db =
  Kre.Db.Make
    (Kre_db_mariadb.Driver)
    (struct
      let url = url
      let size = 2
    end)

module Cats = Cats_db_service.Make (Db)

let app =
  Dream.test (Kre.App.handler [ Cats_controller.register (module Cats) ])

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
          Alcotest.test_case "[@@transactional]: Ok commits, Error rolls back"
            `Quick (fun () ->
              let batch =
                Dream.test
                  (Kre.App.handler [ Batch_controller.register (module Db) ])
              in
              let post note =
                Dream.status_to_int
                  (Dream.status
                     (batch
                        (Dream.request ~method_:`POST ~target:"/batch"
                           (Printf.sprintf
                              {|{"name":"tx","age":1,"breed":"persian","note":"%s"}|}
                              note))))
              in
              let before = List.length (Lwt_main.run (Cats.find_all ())) in
              let committed = post "ok" in
              let rolled_back = post "fail" in
              Alcotest.(check (triple int int int))
                "statuses and rows"
                (204, 409, before + 1)
                ( committed,
                  rolled_back,
                  List.length (Lwt_main.run (Cats.find_all ())) ));
          Alcotest.test_case "crud: for_insert, for_update, delete" `Quick
            (fun () ->
              let module Crud = Cats_crud.Make (Kre_db_mariadb.Sql) in
              let tom = Option.get (Lwt_main.run (Cats.find Cat.Id.first)) in
              let name conn id =
                Lwt.map
                  (Option.fold ~none:"gone" ~some:(fun (cat : Cat.t) ->
                       Cat.Name.to_repr cat.name))
                  (Crud.Single.find conn ~id Cat.of_row)
              in
              Alcotest.(check (list string))
                "inserted, renamed, gone"
                [ "tom"; "thomas"; "gone" ]
                (Lwt_main.run
                   (Db.with_conn (fun conn ->
                        let%lwt inserted =
                          Cat.for_insert tom (Crud.insert conn)
                        in
                        let id = Option.get inserted.insert_id in
                        let%lwt first = name conn id in
                        let%lwt _ =
                          Cat.for_update
                            {
                              tom with
                              id =
                                Result.get_ok (Cat.Id.of_repr (Int64.to_int id));
                              name = Result.get_ok (Cat.Name.of_repr "thomas");
                            }
                            (Crud.update conn)
                        in
                        let%lwt renamed = name conn id in
                        let%lwt _ = Crud.delete conn ~id in
                        let%lwt gone = name conn id in
                        Lwt.return [ first; renamed; gone ]))));
          Alcotest.test_case "live: committed writes reach subscribers" `Quick
            (fun () ->
              let module Sql = Cats_sql.Make (Kre_db_mariadb.Sql) in
              let changes, stop = Kre.Live.subscribe [ "cats" ] in
              let insert result =
                ignore
                  (Lwt_main.run
                     (Db.transaction (fun conn ->
                          let%lwt _ =
                            Sql.insert conn ~name:"ghost" ~age:1L
                              ~breed:"persian"
                          in
                          Lwt.return result)))
              in
              insert (Error ());
              let rolled_back = Lwt_stream.get_available changes in
              insert (Ok ());
              stop ();
              Alcotest.(check (pair (list string) (list string)))
                "only the commit" ([], [ "cats" ])
                (rolled_back, Lwt_stream.get_available changes));
          Alcotest.test_case "transaction rolls back on Error" `Quick (fun () ->
              let attempt =
                Lwt_main.run
                  (Db.transaction (fun conn ->
                       let module Sql = Cats_sql.Make (Kre_db_mariadb.Sql) in
                       let%lwt _ =
                         Sql.insert conn ~name:"ghost" ~age:1L ~breed:"persian"
                       in
                       Lwt.return_error "abort"))
              in
              Alcotest.(check (pair (result reject string) int))
                "rolled back" (Error "abort", 3)
                ( Result.map ignore attempt,
                  List.length (Lwt_main.run (Cats.find_all ())) ));
          Alcotest.test_case "with_conn and transaction join an open one" `Quick
            (fun () ->
              let module Sql = Cats_sql.Make (Kre_db_mariadb.Sql) in
              let changes, stop = Kre.Live.subscribe [ "cats" ] in
              let attempt =
                Lwt_main.run
                  (Db.transaction (fun _ ->
                       let%lwt _ =
                         Db.with_conn (fun conn ->
                             Sql.insert conn ~name:"ghost" ~age:1L
                               ~breed:"persian")
                       in
                       let%lwt inner =
                         Db.transaction (fun conn ->
                             Lwt.map Result.ok
                               (Sql.insert conn ~name:"ghost" ~age:1L
                                  ~breed:"persian"))
                       in
                       Lwt.return (Result.bind inner (fun _ -> Error "abort"))))
              in
              stop ();
              Alcotest.(check (triple (result reject string) int (list string)))
                "all rolled back, nothing published" (Error "abort", 3, [])
                ( Result.map ignore attempt,
                  List.length (Lwt_main.run (Cats.find_all ())),
                  Lwt_stream.get_available changes ));
        ] );
    ]
```

`Kre.Db.Make (Driver) (struct let url = … let size = 2 end)` is `TypeOrmModule.forRoot`. Async initialization is `let%lwt` in `main.ml` or `~on_start` (see [Lifecycle events](lifecycle-events.md)).

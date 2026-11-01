let url =
  match Sys.getenv_opt "KRE_TEST_PG_URL" with
  | Some url -> url
  | None ->
      prerr_endline
        "set KRE_TEST_PG_URL, e.g. postgresql://kre@127.0.0.1:5499/kre_test";
      exit 2

module Db =
  Kre.Db.Make
    (Kre_db_postgresql.Driver)
    (struct
      let url = url
      let size = 2
    end)

module Crud = Cats_pg.Make (Kre_db_postgresql.Sql)

let tom =
  {
    Cat.id = Cat.Id.first;
    name = Result.get_ok (Cat.Name.of_repr "tom");
    age = Result.get_ok (Cat.Age.of_repr 3);
    breed = Result.get_ok (Cat.Breed.of_repr "siamese");
  }

let names () =
  Lwt_main.run
    (Db.with_conn (fun conn ->
         Lwt.map
           (List.map (fun (cat : Cat.t) -> Cat.Name.to_repr cat.name))
           (Crud.List.all conn Cat.of_row)))

let () =
  Lwt_main.run
    (Db.with_conn (fun conn ->
         let%lwt () =
           Kre_db_postgresql.Driver.execute conn
             "DROP TABLE IF EXISTS kre_migrations"
         in
         let%lwt () =
           Kre_db_postgresql.Driver.execute conn "DROP TABLE IF EXISTS cats"
         in
         let%lwt () =
           Kre_db_postgresql.Driver.execute conn "DROP TABLE IF EXISTS kre_jobs"
         in
         let%lwt () =
           Kre_db_postgresql.Driver.execute conn
             (Kre.Table.ddl Postgresql Kre.Job.table)
         in
         let%lwt () =
           Kre_db_postgresql.Driver.execute conn
             "DROP TABLE IF EXISTS kre_locks"
         in
         let%lwt () =
           Kre_db_postgresql.Driver.execute conn
             (Kre.Table.ddl Postgresql Kre.Lock.table)
         in
         let%lwt _ = Crud.create_cats conn in
         let%lwt _ = Crud.create_index_cats_breed conn in
         Lwt.return_unit));
  Alcotest.run "cats on postgresql"
    [
      ( "sqlgg",
        [
          Alcotest.test_case "insert gives the serial id" `Quick (fun () ->
              let inserted =
                Lwt_main.run
                  (Db.with_conn (fun conn ->
                       Cat.for_insert tom (Crud.insert conn)))
              in
              Alcotest.(check (pair int64 (option int64)))
                "affected, id" (1L, Some 1L)
                (inserted.affected_rows, inserted.insert_id));
          Alcotest.test_case "find, update through for_update, delete" `Quick
            (fun () ->
              let name conn =
                Lwt.map
                  (Option.fold ~none:"gone" ~some:(fun (cat : Cat.t) ->
                       Cat.Name.to_repr cat.name))
                  (Crud.Single.find conn ~id:1L Cat.of_row)
              in
              Alcotest.(check (list string))
                "found, renamed, gone"
                [ "tom"; "1"; "thomas"; "1"; "gone" ]
                (Lwt_main.run
                   (Db.with_conn (fun conn ->
                        let%lwt found = name conn in
                        let%lwt updated =
                          Cat.for_update
                            {
                              tom with
                              name = Result.get_ok (Cat.Name.of_repr "thomas");
                            }
                            (Crud.update conn)
                        in
                        let%lwt renamed = name conn in
                        let%lwt deleted = Crud.delete conn ~id:1L in
                        let%lwt gone = name conn in
                        Lwt.return
                          [
                            found;
                            Int64.to_string updated.affected_rows;
                            renamed;
                            Int64.to_string deleted.affected_rows;
                            gone;
                          ]))));
          Alcotest.test_case
            "transactions: Error rolls back, Ok commits and goes live" `Quick
            (fun () ->
              let changes, stop = Kre.Live.subscribe [ "cats" ] in
              let insert result =
                ignore
                  (Lwt_main.run
                     (Db.transaction (fun conn ->
                          let%lwt _ = Cat.for_insert tom (Crud.insert conn) in
                          Lwt.return result)))
              in
              insert (Error ());
              let rolled_back = names () in
              insert (Ok ());
              stop ();
              Alcotest.(
                check (triple (list string) (list string) (list string)))
                "rows and changes"
                ([], [ "tom" ], [ "cats" ])
                (rolled_back, names (), Lwt_stream.get_available changes));
        ] );
      ( "jobs",
        [
          Alcotest.test_case
            "enqueue in a transaction, a failure waits to retry" `Quick
            (fun () ->
              let module Jobs =
                Kre.Job.Make
                  (Db)
                  (struct
                    let poll = 0.1
                    let attempts = 3
                  end) in
              let queue = Kre.Job.queue "greet" (module Cat) in
              let seen = ref [] in
              Jobs.register
                (Kre.Job.handle queue (fun (cat : Cat.t) ->
                     let name = Cat.Name.to_repr cat.name in
                     seen := name :: !seen;
                     Lwt.return
                       (match name with
                       | "tom" -> Error "tom is shy"
                       | _ -> Ok ())));
              let enqueue result cat =
                ignore
                  (Lwt_main.run
                     (Db.transaction (fun _ ->
                          Lwt.map (fun () -> result) (Jobs.enqueue queue cat))))
              in
              enqueue (Error ()) tom;
              enqueue (Ok ())
                { tom with name = Result.get_ok (Cat.Name.of_repr "felix") };
              enqueue (Ok ()) tom;
              let ran = Lwt_main.run (Jobs.drain ()) in
              let left =
                Lwt_main.run
                  (Db.query "SELECT status, attempts, last_error FROM kre_jobs"
                     [])
              in
              Alcotest.(
                check (triple int (list string) (list (list (option string)))))
                "two ran, tom waits for a retry"
                ( 2,
                  [ "felix"; "tom" ],
                  [ [ Some "queued"; Some "1"; Some "tom is shy" ] ] )
                (ran, List.sort String.compare !seen, left));
          Alcotest.test_case "the dashboard lists and deletes jobs" `Quick
            (fun () ->
              let module Jobs =
                Kre.Job.Make
                  (Db)
                  (struct
                    let poll = 0.1
                    let attempts = 3
                  end) in
              let handler = Dream.test (Kre.App.handler [ Jobs.dashboard ]) in
              let call method_ target =
                let response = handler (Dream.request ~method_ ~target "") in
                ( Dream.status_to_int (Dream.status response),
                  Lwt_main.run (Dream.body response) )
              in
              let listed () =
                List.map
                  (fun job ->
                    Yojson.Basic.Util.(
                      to_string (member "queue" job)
                      ^ " "
                      ^ to_string (member "status" job)))
                  (Yojson.Basic.Util.to_list
                     (Yojson.Basic.from_string
                        (snd (call `GET "/__kre/jobs.json"))))
              in
              let before = listed () in
              let id =
                Option.value ~default:""
                  (List.hd
                     (List.hd
                        (Lwt_main.run (Db.query "SELECT id FROM kre_jobs" []))))
              in
              let deleted =
                fst (call `POST ("/__kre/jobs/" ^ id ^ "/delete"))
              in
              Alcotest.(check (triple (list string) int (list string)))
                "listed, deleted, gone"
                ([ "greet queued" ], 303, [])
                (before, deleted, listed ()));
        ] );
      ( "locks",
        [
          Alcotest.test_case "one holder at a time, then free again" `Quick
            (fun () ->
              let module Lock = Kre.Lock.Make (Db) in
              let ran = ref 0 in
              let job () =
                Lock.exclusive "nightly" (fun () ->
                    incr ran;
                    Lwt_unix.sleep 0.2)
              in
              Lwt_main.run (Lwt.join [ job (); job () ]);
              let together = !ran in
              Lwt_main.run (job ());
              Alcotest.(check (pair int int)) "runs" (1, 2) (together, !ran));
        ] );
      ( "migrations",
        [
          Alcotest.test_case "up, then down" `Quick (fun () ->
              let migrations =
                Result.get_ok
                  (Kre.Migration.of_files
                     [
                       ( "20260101000000_dogs.sql",
                         "-- migrate:up\n\
                          CREATE TABLE dogs (id SERIAL PRIMARY KEY);\n\
                          -- migrate:down\n\
                          DROP TABLE dogs;\n" );
                     ])
              in
              let applied, rolled =
                Lwt_main.run
                  (Db.with_conn (fun conn ->
                       let%lwt applied =
                         Kre.Migration.up
                           (module Kre_db_postgresql.Driver)
                           conn migrations
                       in
                       let%lwt rolled =
                         Kre.Migration.down
                           (module Kre_db_postgresql.Driver)
                           conn migrations
                       in
                       Lwt.return (List.length applied, Option.is_some rolled)))
              in
              Alcotest.(check (pair int bool))
                "applied, rolled back" (1, true) (applied, rolled));
        ] );
    ]

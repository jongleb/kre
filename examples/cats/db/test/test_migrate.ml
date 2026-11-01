let url = Option.value (Sys.getenv_opt "KRE_TEST_DB_URL") ~default:""

let versions migrations =
  List.map (fun (migration : Kre.Migration.t) -> migration.version) migrations

let () =
  let migrations = Result.get_ok (Kre.Migration.load "../migrations") in
  let run f =
    Lwt_main.run
      (Lwt.bind (Kre_db_mariadb.Driver.connect url) (fun conn ->
           Lwt.finalize
             (fun () -> f conn)
             (fun () -> Kre_db_mariadb.Driver.close conn)))
  in
  run (fun conn ->
      Lwt_list.iter_s
        (Kre_db_mariadb.Driver.execute conn)
        [
          "DROP TABLE IF EXISTS kre_migrations";
          "DROP TABLE IF EXISTS owners";
          "DROP TABLE IF EXISTS cats";
        ]);
  let status () =
    List.map
      (fun ((migration : Kre.Migration.t), state) ->
        ( migration.version,
          match state with
          | Kre.Migration.Applied -> "applied"
          | Kre.Migration.Pending -> "pending" ))
      (run (fun conn ->
           Kre.Migration.status (module Kre_db_mariadb.Driver) conn migrations))
  in
  Alcotest.run "migrations"
    [
      ( "mariadb",
        [
          Alcotest.test_case "files parse into statements" `Quick (fun () ->
              Alcotest.(check (list (pair int int)))
                "up/down"
                [ (1, 1); (2, 2) ]
                (List.map
                   (fun (migration : Kre.Migration.t) ->
                     (List.length migration.up, List.length migration.down))
                   migrations));
          Alcotest.test_case "empty database: everything pending" `Quick
            (fun () ->
              Alcotest.(check (list (pair string string)))
                "status"
                [ ("0001_cats", "pending"); ("0002_owners", "pending") ]
                (status ()));
          Alcotest.test_case "up applies in order, then nothing" `Quick
            (fun () ->
              let first =
                run (fun conn ->
                    Kre.Migration.up
                      (module Kre_db_mariadb.Driver)
                      conn migrations)
              in
              let second =
                run (fun conn ->
                    Kre.Migration.up
                      (module Kre_db_mariadb.Driver)
                      conn migrations)
              in
              Alcotest.(check (pair (list string) (list string)))
                "applied"
                ([ "0001_cats"; "0002_owners" ], [])
                (versions first, versions second));
          Alcotest.test_case "the schema is really there" `Quick (fun () ->
              Alcotest.(check (list string))
                "tables"
                [ "cats"; "kre_migrations"; "owners" ]
                (run (fun conn ->
                     Kre_db_mariadb.Driver.strings conn
                       "SELECT table_name FROM information_schema.tables WHERE \
                        table_schema = DATABASE() ORDER BY table_name")));
          Alcotest.test_case "down rolls back the last one" `Quick (fun () ->
              Alcotest.(check (option string))
                "rolled back" (Some "0002_owners")
                (Option.map
                   (fun (migration : Kre.Migration.t) -> migration.version)
                   (run (fun conn ->
                        Kre.Migration.down
                          (module Kre_db_mariadb.Driver)
                          conn migrations)));
              Alcotest.(check (list (pair string string)))
                "status"
                [ ("0001_cats", "applied"); ("0002_owners", "pending") ]
                (status ()));
        ] );
    ]

let url = Option.value (Sys.getenv_opt "FORGE_TEST_DB_URL") ~default:""

let versions migrations =
  List.map (fun (migration : Forge.Migration.t) -> migration.version) migrations

let () =
  let migrations = Result.get_ok (Forge.Migration.load "../migrations") in
  let run f =
    Lwt_main.run
      (Lwt.bind (Forge_db_mariadb.Driver.connect url) (fun conn ->
           Lwt.finalize
             (fun () -> f conn)
             (fun () -> Forge_db_mariadb.Driver.close conn)))
  in
  run (fun conn ->
      Lwt_list.iter_s
        (Forge_db_mariadb.Driver.execute conn)
        [
          "DROP TABLE IF EXISTS forge_migrations";
          "DROP TABLE IF EXISTS owners";
          "DROP TABLE IF EXISTS cats";
        ]);
  let status () =
    List.map
      (fun ((migration : Forge.Migration.t), state) ->
        ( migration.version,
          match state with
          | Forge.Migration.Applied -> "applied"
          | Forge.Migration.Pending -> "pending" ))
      (run (fun conn ->
           Forge.Migration.status
             (module Forge_db_mariadb.Driver)
             conn migrations))
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
                   (fun (migration : Forge.Migration.t) ->
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
                    Forge.Migration.up
                      (module Forge_db_mariadb.Driver)
                      conn migrations)
              in
              let second =
                run (fun conn ->
                    Forge.Migration.up
                      (module Forge_db_mariadb.Driver)
                      conn migrations)
              in
              Alcotest.(check (pair (list string) (list string)))
                "applied"
                ([ "0001_cats"; "0002_owners" ], [])
                (versions first, versions second));
          Alcotest.test_case "the schema is really there" `Quick (fun () ->
              Alcotest.(check (list string))
                "tables"
                [ "cats"; "forge_migrations"; "owners" ]
                (run (fun conn ->
                     Forge_db_mariadb.Driver.strings conn
                       "SELECT table_name FROM information_schema.tables WHERE \
                        table_schema = DATABASE() ORDER BY table_name")));
          Alcotest.test_case "down rolls back the last one" `Quick (fun () ->
              Alcotest.(check (option string))
                "rolled back" (Some "0002_owners")
                (Option.map
                   (fun (migration : Forge.Migration.t) -> migration.version)
                   (run (fun conn ->
                        Forge.Migration.down
                          (module Forge_db_mariadb.Driver)
                          conn migrations)));
              Alcotest.(check (list (pair string string)))
                "status"
                [ ("0001_cats", "applied"); ("0002_owners", "pending") ]
                (status ()));
        ] );
    ]

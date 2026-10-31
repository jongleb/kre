let env pairs name = List.assoc_opt name pairs

let () =
  Alcotest.run "config"
    [
      ( "deriving config",
        [
          Alcotest.test_case "defaults and parsing" `Quick (fun () ->
              let config =
                Result.get_ok
                  (Config.load
                     ~env:
                       (env
                          [
                            ("SESSION_SECRET", "s3cret");
                            ("DEBUG", "yes");
                            ("CORS_ORIGINS", "a.io, b.io");
                          ])
                     ())
              in
              Alcotest.(check (triple int bool (list string)))
                "fields"
                (8080, true, [ "a.io"; "b.io" ])
                (config.port, config.debug, config.origins));
          Alcotest.test_case "every error at once" `Quick (fun () ->
              Alcotest.(check (result reject (list string)))
                "errors"
                (Error
                   [
                     "PORT: must be an integer: 'abc'";
                     "SESSION_SECRET: missing";
                     "ADMIN_EMAIL: must be an email address: 'nope'";
                   ])
                (Result.map ignore
                   (Config.load
                      ~env:(env [ ("PORT", "abc"); ("ADMIN_EMAIL", "nope") ])
                      ())));
          Alcotest.test_case "pp hides secrets" `Quick (fun () ->
              Alcotest.(check string)
                "printed"
                "PORT=8080\n\
                 DEBUG=false\n\
                 CORS_ORIGINS=\n\
                 SESSION_SECRET=***\n\
                 ADMIN_EMAIL=me@cats.io\n\
                 DATABASE_URL=\n\
                 MIGRATIONS=examples/cats/db/migrations\n\
                 WEB_DIR=_build/default/examples/cats/web"
                (Format.asprintf "%a" Config.pp
                   (Result.get_ok
                      (Config.load
                         ~env:
                           (env
                              [
                                ("SESSION_SECRET", "s3cret");
                                ("ADMIN_EMAIL", "me@cats.io");
                              ])
                         ()))));
          Alcotest.test_case "profile layers: env > <profile>.env > default.env"
            `Quick (fun () ->
              let dir = Filename.temp_dir "forge" "config" in
              let write name lines =
                Out_channel.with_open_text (Filename.concat dir name) (fun oc ->
                    List.iter (fun line -> output_string oc (line ^ "\n")) lines)
              in
              write "default.env"
                [ "# defaults"; "PORT=1"; "DEBUG=no"; "SESSION_SECRET='x'" ];
              write "test.env" [ "export PORT=2"; "DEBUG=\"yes\"" ];
              let layered =
                Forge.Config.profile ~dir
                  ~env:(env [ ("FORGE_ENV", "test"); ("DEBUG", "0") ])
                  ()
              in
              Alcotest.(check (list (option string)))
                "lookups"
                [ Some "2"; Some "0"; Some "x"; None ]
                (List.map layered [ "PORT"; "DEBUG"; "SESSION_SECRET"; "NOPE" ]));
        ] );
    ]

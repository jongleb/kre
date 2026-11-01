let app = [%wire]

let handler =
  Dream.test (Forge.App.handler (Forge.Live.controller :: app.controllers))

let call ?token ?(body = "") method_ target =
  let response =
    handler
      (Dream.request ~method_ ~target
         ~headers:
           (Option.fold ~none:[]
              ~some:(fun token -> [ ("Authorization", "Bearer " ^ token) ])
              token)
         body)
  in
  ( Dream.status_to_int (Dream.status response),
    Yojson.Basic.from_string
      (match Lwt_main.run (Dream.body response) with
      | "" -> "null"
      | body -> body) )

let text name json =
  Yojson.Basic.Util.to_string (Yojson.Basic.Util.member name json)

let number name json =
  Yojson.Basic.Util.to_int (Yojson.Basic.Util.member name json)

let login email = Printf.sprintf {|{"email":"%s","password":"whiskers1"}|} email

let token email =
  text "token" (snd (call ~body:(login email) `POST "/auth/signup"))

let cat token name =
  number "id"
    (snd
       (call ~token
          ~body:(Printf.sprintf {|{"name":"%s","age":2}|} name)
          `POST "/cats"))

let adopt token id =
  fst
    (call ~token ~body:(Printf.sprintf {|{"cat_id":%d}|} id) `POST "/adoptions")

let names () =
  List.map (text "name") (Yojson.Basic.Util.to_list (snd (call `GET "/cats")))

let () =
  Lwt_main.run
    (let%lwt () = app.on_start () in
     let%lwt conn =
       Forge_db_mariadb.Driver.connect Settings.config.database_url
     in
     let%lwt () =
       Lwt_list.iter_s
         (fun table ->
           Forge_db_mariadb.Driver.execute conn ("DELETE FROM " ^ table))
         [ "adoptions"; "credentials"; "cats"; "users" ]
     in
     Forge_db_mariadb.Driver.close conn);
  let boss = token "boss@shelter.test" in
  let ann = token "ann@shelter.test" in
  let bob = token "bob@shelter.test" in
  Alcotest.run "shelter"
    [
      ( "auth",
        [
          Alcotest.test_case "ADMIN_EMAIL signs up as admin" `Quick (fun () ->
              Alcotest.(check (list string))
                "roles" [ "admin"; "member" ]
                (List.map
                   (fun token ->
                     text "role" (snd (call ~token `GET "/auth/me")))
                   [ boss; ann ]));
          Alcotest.test_case "an email signs up once" `Quick (fun () ->
              Alcotest.(check int)
                "conflict" 409
                (fst
                   (call ~body:(login "ann@shelter.test") `POST "/auth/signup")));
          Alcotest.test_case "a short password is 422" `Quick (fun () ->
              Alcotest.(check (pair int string))
                "rule" (422, "min_length")
                (let status, json =
                   call
                     ~body:{|{"email":"cid@shelter.test","password":"short"}|}
                     `POST "/auth/signup"
                 in
                 ( status,
                   text "rule"
                     (List.hd
                        (Yojson.Basic.Util.to_list
                           (Yojson.Basic.Util.member "errors" json))) )));
          Alcotest.test_case "login checks the password" `Quick (fun () ->
              Alcotest.(check (list int))
                "statuses" [ 200; 401; 401 ]
                (List.map
                   (fun body -> fst (call ~body `POST "/auth/login"))
                   [
                     login "ann@shelter.test";
                     {|{"email":"ann@shelter.test","password":"whiskers2"}|};
                     login "nobody@shelter.test";
                   ]));
          Alcotest.test_case "no token is 401, a forged one too" `Quick
            (fun () ->
              Alcotest.(check (list int))
                "statuses" [ 401; 401 ]
                [
                  fst (call `GET "/auth/me");
                  fst (call ~token:(ann ^ "x") `GET "/auth/me");
                ]);
        ] );
      ( "cats",
        [
          Alcotest.test_case "only an admin admits a cat" `Quick (fun () ->
              Alcotest.(check int)
                "member" 403
                (fst
                   (call ~token:ann ~body:{|{"name":"tom","age":2}|} `POST
                      "/cats"));
              List.iter
                (fun name -> ignore (cat boss name))
                [ "tom"; "felix"; "kitty" ];
              Alcotest.(check (list string))
                "available"
                [ "tom"; "felix"; "kitty" ]
                (names ()));
          Alcotest.test_case "an unknown cat is 404" `Quick (fun () ->
              Alcotest.(check int) "status" 404 (fst (call `GET "/cats/999999")));
        ] );
      ( "adoptions",
        [
          Alcotest.test_case "[@@transactional]: a cat is adopted once" `Quick
            (fun () ->
              let ids =
                List.map (number "id")
                  (Yojson.Basic.Util.to_list (snd (call `GET "/cats")))
              in
              let changes, stop =
                Forge.Live.subscribe [ "cats"; "adoptions" ]
              in
              let first = adopt ann (List.nth ids 0) in
              let published = Lwt_stream.get_available changes in
              let again = adopt bob (List.nth ids 0) in
              let refused = Lwt_stream.get_available changes in
              stop ();
              Alcotest.(check (list int))
                "statuses" [ 201; 409 ] [ first; again ];
              Alcotest.(check (pair (list string) (list string)))
                "live"
                ([ "adoptions"; "cats" ], [])
                (List.sort String.compare published, refused);
              Alcotest.(check (list string))
                "available" [ "felix"; "kitty" ] (names ()));
          Alcotest.test_case "the third adoption rolls back the cat" `Quick
            (fun () ->
              let ids =
                List.map (number "id")
                  (Yojson.Basic.Util.to_list (snd (call `GET "/cats")))
              in
              Alcotest.(check (list int))
                "statuses" [ 201; 409 ]
                (List.map (adopt ann) ids);
              Alcotest.(check (list string)) "available" [ "kitty" ] (names ());
              Alcotest.(check int)
                "mine" 2
                (List.length
                   (Yojson.Basic.Util.to_list
                      (snd (call ~token:ann `GET "/adoptions/mine")))));
        ] );
      ( "commands",
        [
          Alcotest.test_case "seed and signup run with wired providers" `Quick
            (fun () ->
              let run arguments =
                match Forge.Command.invoke app.commands arguments with
                | Run command -> Lwt_main.run (command ())
                | Serve | Usage _ | Invalid _ -> Alcotest.fail "not a command"
              in
              run [ "seed"; "--count"; "2" ];
              run
                [
                  "signup";
                  "--email";
                  "dan@shelter.test";
                  "--password";
                  "whiskers1";
                ];
              Alcotest.(check (pair (list string) int))
                "kittens and a login"
                ([ "kitten 1"; "kitten 2" ], 200)
                ( List.filter (String.starts_with ~prefix:"kitten") (names ()),
                  fst
                    (call ~body:(login "dan@shelter.test") `POST "/auth/login")
                ));
        ] );
      ( "authorize",
        [
          Alcotest.test_case "owner or admin renames a cat" `Quick (fun () ->
              let mine =
                number "cat_id"
                  (List.hd
                     (Yojson.Basic.Util.to_list
                        (snd (call ~token:ann `GET "/adoptions/mine"))))
              in
              let rename token id name =
                fst
                  (call ~token
                     ~body:(Printf.sprintf {|{"name":"%s"}|} name)
                     `PUT
                     ("/cats/" ^ string_of_int id))
              in
              Alcotest.(check (list int))
                "statuses" [ 200; 403; 200; 404 ]
                (List.map
                   (fun (token, id, name) -> rename token id name)
                   [
                     (ann, mine, "tommy");
                     (bob, mine, "bobby");
                     (boss, mine, "thomas");
                     (boss, 999999, "ghost");
                   ]);
              Alcotest.(check string)
                "name" "thomas"
                (text "name" (snd (call `GET ("/cats/" ^ string_of_int mine)))));
        ] );
    ]

let app = [%wire]

let handler =
  Dream.test (Kre.App.handler (Kre.Live.controller :: app.controllers))

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
       Kre_db_mariadb.Driver.connect Settings.config.database_url
     in
     let%lwt () =
       Lwt_list.iter_s
         (fun table ->
           Kre_db_mariadb.Driver.execute conn ("DELETE FROM " ^ table))
         [ "kre_jobs"; "adoptions"; "credentials"; "cats"; "users" ]
     in
     Kre_db_mariadb.Driver.close conn);
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
          Alcotest.test_case "[@@check]: an email signs up once" `Quick
            (fun () ->
              let status, json =
                call ~body:(login "ann@shelter.test") `POST "/auth/signup"
              in
              let error =
                List.hd
                  (Yojson.Basic.Util.to_list
                     (Yojson.Basic.Util.member "errors" json))
              in
              Alcotest.(check (triple int string (list string)))
                "taken"
                (422, "unique", [ "email" ])
                ( status,
                  text "rule" error,
                  List.map Yojson.Basic.Util.to_string
                    (Yojson.Basic.Util.to_list
                       (Yojson.Basic.Util.member "path" error)) ));
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
          Alcotest.test_case "the catalog comes in pages" `Quick (fun () ->
              let page query =
                let status, json = call `GET ("/cats/catalog" ^ query) in
                match status with
                | 200 ->
                    Printf.sprintf "%d of %d: %s" (number "page" json)
                      (number "total" json)
                      (String.concat ","
                         (List.map (text "name")
                            (Yojson.Basic.Util.to_list
                               (Yojson.Basic.Util.member "items" json))))
                | status -> string_of_int status
              in
              Alcotest.(check (list string))
                "pages"
                [
                  "1 of 3: tom,felix";
                  "2 of 3: kitty";
                  "400";
                  "400";
                  "1 of 1: kitty";
                  "1 of 3: tom,felix";
                  "1 of 0: ";
                  "400";
                ]
                (List.map page
                   [
                     "?size=2";
                     "?page=2&size=2";
                     "?size=0";
                     "?page=x";
                     "?name=itt";
                     "?status=available&size=2";
                     "?age_min=3";
                     "?status=lost";
                   ]));
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
              let changes, stop = Kre.Live.subscribe [ "cats"; "adoptions" ] in
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
      ( "jobs",
        [
          Alcotest.test_case
            "a letter per committed adoption, none for the rolled back one"
            `Quick (fun () ->
              let letters () =
                let user =
                  Printf.sprintf "user %d "
                    (number "id" (snd (call ~token:ann `GET "/auth/me")))
                in
                List.length
                  (List.filter
                     (fun (letter : Kre.Mail.t) ->
                       String.starts_with ~prefix:user letter.text)
                     (Mail.sent ()))
              in
              let rec wait tries =
                match (letters (), tries) with
                | 2, _ | _, 0 -> ()
                | _ ->
                    Lwt_main.run (Lwt_unix.sleep 0.05);
                    wait (tries - 1)
              in
              wait 100;
              Lwt_main.run (Lwt_unix.sleep 0.3);
              Alcotest.(check int) "letters to ann" 2 (letters ()));
        ] );
      ( "relations",
        [
          Alcotest.test_case "cats of many owners in one query" `Quick
            (fun () ->
              let module Db = Database.Make (Settings) in
              let module Cats = Cats_service.Make (Db) in
              let id token =
                Result.get_ok
                  (User.Id.of_repr
                     (number "id" (snd (call ~token `GET "/auth/me"))))
              in
              let owned = Lwt_main.run (Cats.owned_by [ id ann; id bob ]) in
              Alcotest.(check (pair int int))
                "ann and bob" (2, 0)
                (List.length (owned (id ann)), List.length (owned (id bob))));
        ] );
      ( "commands",
        [
          Alcotest.test_case "seed and signup run with wired providers" `Quick
            (fun () ->
              let run arguments =
                match Kre.Command.invoke app.commands arguments with
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
          Alcotest.test_case
            "owner or admin renames a cat; a stale version is 409" `Quick
            (fun () ->
              let mine =
                number "cat_id"
                  (List.hd
                     (Yojson.Basic.Util.to_list
                        (snd (call ~token:ann `GET "/adoptions/mine"))))
              in
              let version id =
                Option.value ~default:0
                  (Yojson.Basic.Util.to_int_option
                     (Yojson.Basic.Util.member "version"
                        (snd (call `GET ("/cats/" ^ string_of_int id)))))
              in
              let rename token id ?(version = version id) name =
                fst
                  (call ~token
                     ~body:
                       (Printf.sprintf {|{"name":"%s","version":%d}|} name
                          version)
                     `PUT
                     ("/cats/" ^ string_of_int id))
              in
              let read = version mine in
              Alcotest.(check (list int))
                "statuses"
                [ 200; 409; 403; 200; 404 ]
                (List.map
                   (fun rename -> rename ())
                   [
                     (fun () -> rename ann mine ~version:read "tommy");
                     (fun () -> rename boss mine ~version:read "stale");
                     (fun () -> rename bob mine "bobby");
                     (fun () -> rename boss mine "thomas");
                     (fun () -> rename boss 999999 "ghost");
                   ]);
              Alcotest.(check (pair string int))
                "name and version"
                ("thomas", read + 2)
                ( text "name" (snd (call `GET ("/cats/" ^ string_of_int mine))),
                  version mine ));
        ] );
    ]

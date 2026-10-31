# Testing

Nest: `Test.createTestingModule` с `overrideProvider`. Forge: контейнера нет, подмена — передать другой модуль в `register`; приложение проверяется `Dream.test` без сети.

<!-- $MDX file=../examples/cats/test/test_cats.ml -->
```ocaml
let app =
  let module Fresh = Cats_service.Make () in
  Dream.test (Forge.App.handler [ Cats_controller.register (module Fresh) ])

let call ?(headers = []) ?(body = "") method_ target =
  let response = app (Dream.request ~method_ ~target ~headers body) in
  ( Dream.status_to_int (Dream.status response),
    Lwt_main.run (Dream.body response) )

let status (code, _) = code
let json (_, body) = Yojson.Basic.from_string body

let rules response =
  List.map
    (fun error -> Yojson.Basic.Util.(to_string (member "rule" error)))
    Yojson.Basic.Util.(to_list (member "errors" (json response)))

let tom = {|{"name":"tom","age":3,"breed":"siamese"}|}
let user = [ ("X-User", "ann") ]

let () =
  Alcotest.run "cats"
    [
      ( "controller",
        [
          Alcotest.test_case "empty list" `Quick (fun () ->
              Alcotest.(check (pair int string))
                "empty" (200, "[]") (call `GET "/cats"));
          Alcotest.test_case "guard runs before the body" `Quick (fun () ->
              Alcotest.(check int)
                "missing user" 400
                (status (call ~body:tom `POST "/cats")));
          Alcotest.test_case "body that is not JSON is 400" `Quick (fun () ->
              Alcotest.(check int)
                "bad json" 400
                (status (call ~headers:user ~body:"{" `POST "/cats")));
          Alcotest.test_case "refined field is 422 with its rule" `Quick
            (fun () ->
              let response =
                call ~headers:user
                  ~body:{|{"name":"tom","age":99,"breed":"siamese"}|} `POST
                  "/cats"
              in
              Alcotest.(check (pair int (list string)))
                "range" (422, [ "range" ])
                (status response, rules response));
          Alcotest.test_case "[@validate] reports the field path" `Quick
            (fun () ->
              let response =
                call ~headers:user
                  ~body:
                    {|{"name":"tom","age":3,"breed":"siamese","note":"far too long for a note"}|}
                  `POST "/cats"
              in
              Alcotest.(check (pair int (list string)))
                "max_length" (422, [ "max_length" ])
                (status response, rules response);
              Alcotest.(check (list string))
                "path" [ "note" ]
                Yojson.Basic.Util.(
                  List.map to_string
                    (to_list
                       (member "path"
                          (List.hd (to_list (member "errors" (json response))))))));
          Alcotest.test_case "~strict rejects unknown fields" `Quick (fun () ->
              Alcotest.(check int)
                "extra" 422
                (status
                   (call ~headers:user
                      ~body:{|{"name":"tom","age":3,"breed":"siamese","x":1}|}
                      `POST "/cats")));
          Alcotest.test_case "create answers 201 with the cat" `Quick (fun () ->
              Alcotest.(check (pair int string))
                "created"
                (201, {|{"id":1,"name":"tom","age":3,"breed":"siamese"}|})
                (call ~headers:user ~body:tom `POST "/cats"));
          Alcotest.test_case "path parameter" `Quick (fun () ->
              Alcotest.(check (list int))
                "statuses" [ 200; 404; 404 ]
                (List.map
                   (fun target -> status (call `GET target))
                   [ "/cats/1"; "/cats/9"; "/cats/one" ]));
          Alcotest.test_case "query parameter with default" `Quick (fun () ->
              Alcotest.(check (list (pair int string)))
                "limit"
                [
                  (200, "[]");
                  (200, {|[{"id":1,"name":"tom","age":3,"breed":"siamese"}]|});
                ]
                [ call `GET "/cats?limit=0"; call `GET "/cats" ]);
          Alcotest.test_case "bad query parameter is 400" `Quick (fun () ->
              Alcotest.(check int)
                "limit=x" 400
                (status (call `GET "/cats?limit=x")));
          Alcotest.test_case "paths print urls" `Quick (fun () ->
              Alcotest.(check string)
                "url" "/cats/42"
                (Routes.sprintf
                   (Cats_controller.Paths.find_one ())
                   (Result.get_ok (Cat.Id.of_repr 42))));
          Alcotest.test_case "spec" `Quick (fun () ->
              Alcotest.(check (list (pair string string)))
                "routes"
                [ ("GET", "/cats"); ("GET", "/cats/:id"); ("POST", "/cats") ]
                (List.map
                   (fun (route : Forge.Spec.route) ->
                     (Dream.method_to_string route.verb, route.path))
                   Cats_controller.spec.routes));
        ] );
    ]
```

Уровни в репозитории: cram на вывод ppx (`test/ppx`), alcotest на рантайм (`test/core`), контроллеры через `Dream.test`, e2e — сгенерированный клиент против живого сервера (`examples/cats/client_native`, `client_js`), база — алиас `@db`.

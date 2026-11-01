# Testing

Nest: `Test.createTestingModule` с `overrideProvider`. Kre: контейнера нет, подмена — передать другой модуль в `register`; приложение проверяется `Dream.test` без сети.

<!-- $MDX file=../examples/cats/test/test_cats.ml -->
```ocaml
let app =
  let module Fresh = Cats_service.Make () in
  Dream.test (Kre.App.handler [ Cats_controller.register (module Fresh) ])

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
          Alcotest.test_case "[@@etag]: an unchanged cat is 304" `Quick
            (fun () ->
              let tag =
                Option.value ~default:""
                  (Dream.header
                     (app (Dream.request ~target:"/cats/1" ""))
                     "ETag")
              in
              Alcotest.(check int)
                "not modified" 304
                (status
                   (call ~headers:[ ("If-None-Match", tag) ] `GET "/cats/1")));
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
                   (fun (route : Kre.Spec.route) ->
                     (Dream.method_to_string route.verb, route.path))
                   Cats_controller.spec.routes));
        ] );
    ]
```

Уровни в репозитории: cram на вывод ppx (`test/ppx`), alcotest на рантайм (`test/core`), контроллеры через `Dream.test`, e2e — сгенерированный клиент против живого сервера (`examples/cats/client_native`, `client_js`), база — алиас `@db`.

## Типизированный клиент без сети

Nest проверяет HTTP через supertest, Spring — через MockMvc: запросы собираются строками. В Kre тест может звать тот же сгенерированный клиент, что и фронтенд. `Kre_testing.use` (библиотека `kre-client.testing`) направляет его запросы прямо в обработчик приложения, без порта и сокета. Неверный путь, поле тела или тип ответа ломают компиляцию теста.

<!-- $MDX file=../examples/cats/client_native/test_in_process.ml -->
```ocaml
let tom =
  {
    Create_cat_dto.name = Result.get_ok (Cat.Name.of_repr "tom");
    age = Result.get_ok (Cat.Age.of_repr 3);
    breed = Result.get_ok (Cat.Breed.of_repr "siamese");
    note = "";
  }

module Cats_api =
  [%http_client:
  val find_one : id:Cat.Id.t -> Cat.t [@@get "/cats/:id"]
  val find_all : ?limit:int -> unit -> Cat.t list [@@get "/cats"]
  val create : body:Create_cat_dto.t -> Cat.t [@@post "/cats"]]

module Cats_http = Cats_api (struct
  let url = "http://cats.internal"
  let headers = [ ("X-User", "bob") ]
end)

let outcome = function
  | Ok (cat : Cat.t) -> "ok " ^ Cat.Name.to_repr cat.name
  | Error (Kre_client.Error.Problem problem) ->
      Printf.sprintf "%d %s" problem.status
        (String.concat ","
           (List.map
              (fun (error : Kre_shared.Validation.error) ->
                String.concat "." error.path ^ ":" ^ error.rule)
              problem.errors))
  | Error error -> Kre_client.Error.message error

let () =
  let module Fresh = Cats_service.Make () in
  Kre_testing.use [ Cats_controller.register (module Fresh) ];
  Kre_client.Http.headers := [ ("X-User", "ann") ];
  Lwt_main.run
    (Alcotest_lwt.run "in-process client"
       [
         ( "cats",
           [
             Alcotest_lwt.test_case "typed calls, no socket" `Quick (fun _ () ->
                 let%lwt created = Cats_client.create ~body:tom in
                 let%lwt rejected =
                   Cats_client.create
                     ~body:{ tom with note = "far too long for a note" }
                 in
                 let%lwt missing =
                   Cats_client.find_one ~id:(Result.get_ok (Cat.Id.of_repr 9))
                 in
                 Alcotest.(check (list string))
                   "outcomes"
                   [ "ok tom"; "422 note:max_length"; "404 " ]
                   [ outcome created; outcome rejected; outcome missing ];
                 Lwt.return_unit);
             Alcotest_lwt.test_case "a declared HTTP client" `Quick (fun _ () ->
                 let%lwt created =
                   Cats_http.create ~body:{ tom with note = "" }
                 in
                 let%lwt all = Cats_http.find_all ~limit:1 () in
                 let%lwt missing =
                   Cats_http.find_one ~id:(Result.get_ok (Cat.Id.of_repr 99))
                 in
                 Alcotest.(check (list string))
                   "outcomes"
                   [ "ok tom"; "1 cat"; "404 " ]
                   [
                     outcome created;
                     Result.fold
                       ~ok:(fun cats ->
                         Printf.sprintf "%d cat" (List.length cats))
                       ~error:Kre_client.Error.message all;
                     outcome missing;
                   ];
                 Lwt.return_unit);
           ] );
       ])
```

# OpenAPI и CLI

Контроллер — источник правды. Серверный бинарь с `--emit-spec spec.json` пишет описание всех контроллеров, с `--emit-openapi openapi.json` — документ OpenAPI 3.1. CLI работает по `spec.json`:

<!-- $MDX skip -->
```sh
forge routes --spec spec.json
forge openapi --spec spec.json --out openapi.json --title Cats --version 1.0.0
forge client --spec spec.json --controller cats --out cats_client.ml
forge migrate up --url mariadb://user:pass@localhost/db
forge generate controller dogs
```

`spec` — то, что ppx сгенерировал в контроллере:

<!-- $MDX file=../examples/cats/server/cats_controller.ml -->
```ocaml
[@@@controller "cats"]
[@@@use [ Logger_middleware.use ]]

let find_all (module Cats : Cats_service.S) ?(limit : int = 20) () :
    Cat.t list Lwt.t =
  let%lwt all = Cats.find_all () in
  Lwt.return (List.filteri (fun i _ -> i < limit) all)
[@@get] [@@summary "List cats"]

let find_one (module Cats : Cats_service.S) ~(id : Cat.Id.t) :
    (Cat.t, Forge.Error.t) result Lwt.t =
  let%lwt cat = Cats.find id in
  Lwt.return (Option.to_result cat ~none:(Forge.Error.not_found "cat"))
[@@get ":id"]
[@@summary "Find a cat"]
[@@description "Answers 404 when no cat has this id."]

let create (module Cats : Cats_service.S) ~(user : (string[@guard Auth.user]))
    ~(body : Create_cat_dto.t) : Cat.t Lwt.t =
  Dream.log "%s adds a cat" user;
  Cats.add body
[@@post] [@@status 201]
```


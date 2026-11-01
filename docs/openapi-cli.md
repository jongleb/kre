# OpenAPI and CLI

The controller is the source of truth. The server binary with `--emit-spec spec.json` writes a description of all controllers, and with `--emit-openapi openapi.json` an OpenAPI 3.1 document. The CLI works from `spec.json`:

<!-- $MDX skip -->
```sh
kre routes --spec spec.json
kre openapi --spec spec.json --out openapi.json --title Cats --version 1.0.0
kre client --spec spec.json --controller cats --out cats_client.ml
kre migrate up --url mariadb://user:pass@localhost/db
kre generate controller dogs name:string age:int born:time good:bool
```

`kre generate controller` scaffolds a whole resource: a type with `[@@deriving table, dto]` (fields from `name:type` arguments, types `string`, `int`, `float`, `bool`, `time`; by default `name:string`), a create DTO, an in-memory service (`Make ()`, later replaced by a database-backed service), a CRUD controller and a test with sample values. Everything goes into the existing `shared`/`server` libraries; `[%wire]` and `kre client` pick up the resource on their own; the generated project builds and passes its test (`test/scaffold/new.t`).

`spec` is what the ppx generated in the controller:

<!-- $MDX file=../examples/cats/server/cats_controller.ml -->
```ocaml
[@@@controller "cats"]
[@@@use [ Logger_middleware.use ]]

let find_all (module Cats : Cats_service.S) ~(search : (Cat_search.t[@search]))
    () : Cat.t list Lwt.t =
  let%lwt all = Cats.find_all () in
  Lwt.return
    (List.filteri
       (fun i _ -> i < search.limit)
       (List.filter
          (fun (cat : Cat.t) ->
            Option.fold ~none:true
              ~some:(fun breed ->
                String.equal (Cat.Breed.to_repr breed)
                  (Cat.Breed.to_repr cat.breed))
              search.breed)
          all))
[@@get] [@@summary "List cats"] [@@live [ "cats" ]]

let find_one (module Cats : Cats_service.S) ~(id : Cat.Id.t) :
    (Cat.t, Kre.Error.t) result Lwt.t =
  let%lwt cat = Cats.find id in
  Lwt.return (Option.to_result cat ~none:(Kre.Error.not_found "cat"))
[@@get ":id"]
[@@etag]
[@@summary "Find a cat"]
[@@description "Answers 404 when no cat has this id."]

let create (module Cats : Cats_service.S) ~(user : (string[@guard Auth.user]))
    ~(body : Create_cat_dto.t) : Cat.t Lwt.t =
  Dream.log "%s adds a cat" user;
  Cats.add body
[@@post] [@@status 201]
```


kre new writes a project that builds and passes its own test.

  $ kre new demo
  created demo/.gitignore
  created demo/.ocamlformat
  created demo/bin/dune
  created demo/bin/main.ml
  created demo/dune-project
  created demo/server/dune
  created demo/server/health_controller.ml
  created demo/shared/dune
  created demo/shared/health.ml
  created demo/shared/melange/dune
  created demo/test/dune
  created demo/test/test_health.ml
  $ cd demo
  $ dune build 2>&1
  $ dune test 2>&1 | grep -E "OK|FAIL|Expected|Received"
    [OK]          health          0   GET /health.

A generated resource builds and its CRUD test passes.

  $ kre generate controller cats
  created ./server/cats_controller.ml
  created ./shared/create_cat_dto.ml
  created ./shared/cat.ml
  created ./test/cats/dune
  created ./test/cats/test_cats.ml
  created ./server/cats_service.ml
  created ./server/cats_service.mli
  $ dune build 2>&1
  $ dune test 2>&1 | grep -E "OK|FAIL|Expected|Received"
    [OK]          crud          0   create, read, remove.
    [OK]          crud          1   invalid body is 422.

Fields are name:type; the entity is ready for a table, the test posts sample
values.

  $ kre generate controller dogs name:string age:int born:time good:bool
  created ./server/dogs_controller.ml
  created ./shared/create_dog_dto.ml
  created ./shared/dog.ml
  created ./test/dogs/dune
  created ./test/dogs/test_dogs.ml
  created ./server/dogs_service.ml
  created ./server/dogs_service.mli
  $ cat shared/dog.ml shared/create_dog_dto.ml
  open Jsonkit.Primitives
  
  module Id = Kre_shared.Id.Make ()
  
  type t = {
    id : Id.t; [@primary] [@auto] [@column int]
    name : string; [@size 255] [@validate min_length 1]
    age : int;
    born : Kre_shared.Time.t;
    good : bool;
  }
  [@@deriving table ~name:"dogs", dto]
  open Jsonkit.Primitives
  
  type t = {
    name : string; [@validate min_length 1]
    age : int;
    born : Kre_shared.Time.t;
    good : bool;
  }
  [@@deriving dto ~strict]
  $ dune build 2>&1
  $ dune test 2>&1 | grep -E "OK|FAIL|Expected|Received"
    [OK]          crud          0   create, read, remove.
    [OK]          crud          1   invalid body is 422.
  $ kre generate controller birds wings:triple
  kre: wings:triple: a field is name:type with type string, int, float, bool or time
  [123]

Generating over existing files writes nothing.

  $ kre generate controller cats
  kre: ./server/cats_controller.ml already exists; nothing was written
  [123]
  $ kre generate dto signup && dune build 2>&1
  created ./shared/signup_dto.ml

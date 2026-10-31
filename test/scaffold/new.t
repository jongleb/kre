forge new writes a project that builds and passes its own test.

  $ forge new demo
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

  $ forge generate controller cats
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

Generating over existing files writes nothing.

  $ forge generate controller cats
  forge: ./server/cats_controller.ml already exists; nothing was written
  [123]
  $ forge generate dto signup && dune build 2>&1
  created ./shared/signup_dto.ml

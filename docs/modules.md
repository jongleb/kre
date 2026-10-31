# Modules

Nest: `@Module({ imports, providers, controllers, exports })`. В OCaml это уже есть: модуль — единица кода, `.mli` — exports, библиотека dune — граница пакета, `bin/main.ml` — сборка приложения. Отдельной сущности «модуль Forge» нет.

Провайдер с зависимостями — функтор: его аргументы и есть `imports`.

<!-- $MDX file=../examples/cats/db/cats_db_service.mli -->
```ocaml
module Make (Db : Forge.Db.S with type conn = Forge_db_mariadb.Client.t) : sig
  include Cats_service.S

  val reset : unit -> unit Lwt.t
end
```

Применение — в composition root: `module Cats = Cats_db_service.Make (Db)`, затем `Cats_controller.register (module Cats)`. Порядок применения функторов — порядок инициализации, циклы невыразимы.

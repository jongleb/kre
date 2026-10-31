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

Собирать это руками не нужно. `[%wire]` в `main.ml` — это `@Module` и `@ComponentScan` сразу: ppx при сборке читает каталоги, находит провайдеров (модули с `Make` или `module type S`), сортирует их по зависимостям, применяет функторы и регистрирует контроллеры. Нет провайдера, два кандидата без `[@@@primary]`, цикл — ошибка компиляции с местом в коде.

<!-- $MDX file=../examples/cats/bin/main.ml -->
```ocaml
let () =
  let app = [%wire] in
  let actuator =
    Forge.Actuator.make ~checks:app.health
      ~env:(Config.pairs Settings.config)
      app.controllers
  in
  Forge.App.run ~port:Settings.config.port
    ~middleware:
      [ Dream.logger; actuator.metrics; Web.use ~dir:Settings.config.web ]
    ~on_start:app.on_start ~on_shutdown:app.on_shutdown
    (actuator.controller :: Forge.Live.controller :: app.controllers)
```

Провайдер базы с хуком `on_start` (миграции при старте):

<!-- $MDX file=../examples/cats/db/database.ml -->
```ocaml
module Make (Settings : Settings.S) = struct
  include
    Forge.Db.Make
      (Forge_db_mariadb.Driver)
      (struct
        let url = Settings.database_url
        let size = 4
      end)

  let on_start () =
    with_conn (fun conn ->
        Lwt.map ignore
          (Forge.Migration.up
             (module Forge_db_mariadb.Driver)
             conn
             (Result.get_ok
                (Forge.Migration.of_files [%embed_dir "migrations"]))))

  let ping () =
    Lwt.catch
      (fun () ->
        with_conn (fun conn ->
            Lwt.map
              (fun _ -> Ok ())
              (Forge_db_mariadb.Driver.strings conn "SELECT 1")))
      (fun exn -> Lwt.return_error (Printexc.to_string exn))
  [@@health "db"]
end
```

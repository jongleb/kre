# First steps

Nest: `nest new project` и `main.ts` с `NestFactory.create(AppModule)`. Forge: `forge new project` и `bin/main.ml`, где список контроллеров и есть приложение.

<!-- $MDX skip -->
```sh
forge new shelter
cd shelter && dune build && dune test
dune exec bin/main.exe
```

`bin/main.ml` примера cats — composition root: конфиг, контроллеры с их зависимостями, глобальные middleware.

<!-- $MDX file=../examples/cats/bin/main.ml -->
```ocaml
let () =
  let config = Config.load_exn ~env:(Forge.Config.profile ()) () in
  let database =
    Option.map
      (fun url ->
        let module Db =
          Forge.Db.Make
            (Forge_db_mariadb.Driver)
            (struct
              let url = url
              let size = 4
            end) in
        let module Cats = Cats_db_service.Make (Db) in
        ( Cats_controller.register (module Cats),
          fun () ->
            Db.with_conn (fun conn ->
                Lwt.map ignore
                  (Forge.Migration.up
                     (module Forge_db_mariadb.Driver)
                     conn
                     (Result.get_ok (Forge.Migration.load config.migrations))))
        ))
      config.database_url
  in
  Format.printf "%a@." Config.pp config;
  Forge.App.run ~port:config.port
    ~middleware:[ Dream.logger; Web.use ~dir:config.web ]
    ?on_start:(Option.map snd database)
    [
      Option.fold
        ~none:(Cats_controller.register (module Cats_service))
        ~some:fst database;
    ]
```

Сервер — `Forge.App.run`, то есть `Dream.serve` с роутингом Forge; `Forge.App.handler` даёт тот же `Dream.handler` для тестов и для встраивания в свой `Dream.run`.

# Что не нужно и почему

Эти главы Nest компенсируют отсутствие модульной системы в TypeScript; в OCaml им нечего делать.

- **Circular dependency, `forwardRef`.** Модули и функторы применяются по порядку, цикл — ошибка компиляции.
- **Module reference, Discovery.** Всё, что нужно контроллеру, передано ему явно; искать провайдеры по токену не нужно и невозможно.
- **Lazy-loading modules.** Ленивое значение — `Lazy.t` или функция; отдельного механизма не нужно.
- **Platform agnosticism.** Forge работает поверх Dream и не прячет его: `Dream.request`, `Dream.middleware`, `Dream.response` — часть API.

Composition root, в котором всё это видно сразу:

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


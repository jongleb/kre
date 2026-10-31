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
  Format.printf "%a@." Config.pp config;
  Forge.App.run ~port:config.port ~middleware:[ Dream.logger ]
    [ Cats_controller.register (module Cats_service) ]
```

Сервер — `Forge.App.run`, то есть `Dream.serve` с роутингом Forge; `Forge.App.handler` даёт тот же `Dream.handler` для тестов и для встраивания в свой `Dream.run`.

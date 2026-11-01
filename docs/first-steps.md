# First steps

Nest: `nest new project` и `main.ts` с `NestFactory.create(AppModule)`. Kre: `kre new project` и `bin/main.ml`, где список контроллеров и есть приложение.

<!-- $MDX skip -->
```sh
kre new shelter
cd shelter && dune build && dune test
dune exec bin/main.exe
```

`bin/main.ml` примера cats — composition root: конфиг, контроллеры с их зависимостями, глобальные middleware.

<!-- $MDX file=../examples/cats/bin/main.ml -->
```ocaml
let () =
  let app = [%wire] in
  let actuator =
    Kre.Actuator.make ~checks:app.health ~beans:app.beans
      ~env:(Config.pairs Settings.config)
      app.controllers
  in
  Kre.App.run ~port:Settings.config.port
    ~middleware:
      [ Dream.logger; actuator.metrics; Web.use ~dir:Settings.config.web ]
    ~on_start:app.on_start ~on_shutdown:app.on_shutdown
    (actuator.controller :: Kre.Live.controller :: app.controllers)
```

Сервер — `Kre.App.run`, то есть `Dream.serve` с роутингом Kre; `Kre.App.handler` даёт тот же `Dream.handler` для тестов и для встраивания в свой `Dream.run`.

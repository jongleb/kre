# First steps

`kre new project` creates a project; its entry point is `bin/main.ml`, where the list of controllers is the application.

<!-- $MDX skip -->
```sh
kre new shelter
cd shelter && dune build && dune test
dune exec bin/main.exe
```

The `bin/main.ml` of the cats example is the composition root: config, controllers with their dependencies, global middleware.

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

The server is `Kre.App.run`, that is, `Dream.serve` with Kre routing; `Kre.App.handler` gives the same `Dream.handler` for tests and for embedding into your own `Dream.run`.

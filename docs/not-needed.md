# What is not needed and why

These Nest chapters make up for the lack of a module system in TypeScript; in OCaml they have nothing to do.

- **Circular dependency, `forwardRef`.** Modules and functors are applied in order; a cycle is a compile error.
- **Module reference, Discovery.** Everything a controller needs is passed to it explicitly; looking up providers by token is neither needed nor possible.
- **Lazy-loading modules.** A lazy value is a `Lazy.t` or a function; no separate mechanism is needed.
- **Platform agnosticism.** Kre runs on top of Dream and does not hide it: `Dream.request`, `Dream.middleware`, `Dream.response` are part of the API.

The composition root, where all of this is visible at once:

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


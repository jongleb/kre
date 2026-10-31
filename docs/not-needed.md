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


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
  Format.printf "%a@." Config.pp config;
  Forge.App.run ~port:config.port ~middleware:[ Dream.logger ]
    [ Cats_controller.register (module Cats_service) ]
```


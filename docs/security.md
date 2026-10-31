# Security: helmet, CORS, rate limiting

Nest: `helmet`, `app.enableCors`, `@nestjs/throttler`. Forge: три `Dream.middleware` — подключаются глобально через `Forge.App.run ~middleware`, на контроллер через `[@@@use]`, на маршрут через `[@@use]`.

<!-- $MDX file=examples/hardened.ml -->
```ocaml
let middleware =
  [
    Forge.Secure_headers.middleware ();
    Forge.Cors.middleware ~origins:(Forge.Cors.Only [ "https://cats.example" ])
      ();
    Forge.Rate_limit.middleware ~limit:100 ~window:60. ();
  ]

let main () =
  Forge.App.run ~middleware [ Cats_controller.register (module Cats_service) ]
```

- `Forge.Secure_headers` ставит `Content-Security-Policy`, `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`, `Cross-Origin-Opener-Policy`; HSTS — только с `~transport:(Https_only { max_age })`. Заголовок, который поставил хендлер, не перетирается.
- `Forge.Cors`: `Any | Only [origins]`, cookies — `~credentials:Include`. Preflight (`OPTIONS` с `Access-Control-Request-Method`) отвечается 204 без хендлера.
- `Forge.Rate_limit`: фиксированное окно на ключ (по умолчанию IP клиента), превышение — 429 Problem Details и `Retry-After`. Счётчики в памяти процесса; для нескольких процессов — общий счётчик, фаза 3.

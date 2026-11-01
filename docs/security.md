# Security: helmet, CORS, rate limiting

Nest: `helmet`, `app.enableCors`, `@nestjs/throttler`. Kre: three `Dream.middleware`s, mounted globally through `Kre.App.run ~middleware`, per controller through `[@@@use]`, per route through `[@@use]`.

<!-- $MDX file=examples/hardened.ml -->
```ocaml
let middleware =
  [
    Kre.Secure_headers.middleware ();
    Kre.Cors.middleware ~origins:(Kre.Cors.Only [ "https://cats.example" ]) ();
    Kre.Rate_limit.middleware ~limit:100 ~window:60. ();
  ]

let main () =
  Kre.App.run ~middleware [ Cats_controller.register (module Cats_service) ]
```

- `Kre.Secure_headers` sets `Content-Security-Policy`, `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`, `Cross-Origin-Opener-Policy`; HSTS only with `~transport:(Https_only { max_age })`. A header set by the handler is not overwritten.
- `Kre.Cors`: `Any | Only [origins]`, cookies with `~credentials:Include`. A preflight (`OPTIONS` with `Access-Control-Request-Method`) is answered with 204 without a handler.
- `Kre.Rate_limit`: a fixed window per key (the client IP by default); exceeding it gives 429 Problem Details and `Retry-After`. Counters live in process memory; a shared counter for several processes is phase 3.

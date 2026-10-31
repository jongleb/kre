# Interceptors

Nest: `NestInterceptor` с RxJS вокруг хендлера. Forge: то же делает `Dream.middleware` — у него есть и запрос до, и ответ после.

<!-- $MDX file=examples/timing.ml -->
```ocaml
let use : Dream.middleware =
 fun next request ->
  let started = Unix.gettimeofday () in
  Lwt.map
    (fun response ->
      Dream.add_header response "Server-Timing"
        (Printf.sprintf "app;dur=%.1f"
           ((Unix.gettimeofday () -. started) *. 1000.));
      response)
    (next request)
```

Преобразование ответа — тоже middleware, либо явный `Forge.Response.json` из хендлера (тип результата `Dream.response Lwt.t`). Кэширование и таймауты — фаза 2.

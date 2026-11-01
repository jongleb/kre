# Interceptors

Nest: `NestInterceptor.intercept(context, next)` с RxJS и `@UseInterceptors`. Forge: `Forge.Interceptor.t` — полиморфная функция вокруг **типизированного** результата хендлера, после guards и вокруг разбора параметров (как в Nest):

```ocaml
type t = { around : 'a. Dream.request -> (unit -> ('a, Error.t) result Lwt.t) -> ('a, Error.t) result Lwt.t }
```
```mdx-error
Line 1, characters 25-30:
Error: Unbound module Dream
```

Подключение — `[@@intercept [ … ]]` на хендлер, `[@@@intercept [ … ]]` на контроллер (`@UseInterceptors`). Готовые: `logging` (метод, путь, результат, время), `timeout s` (504), `map_error f` (exception mapping), `tap f`, `chain`.

<!-- $MDX file=examples/audit_controller.ml -->
```ocaml
[@@@controller "audit"]
[@@@intercept [ Forge.Interceptor.logging ]]

let hidden =
  Forge.Interceptor.map_error (fun (error : Forge.Error.t) ->
      match error.code with
      | "not_found" -> Forge.Error.forbidden "hidden"
      | _ -> error)

let calls = ref 0

let counted =
  Forge.Interceptor.tap (fun _ ->
      incr calls;
      Lwt.return_unit)

let secret ~(id : int) : (string, Forge.Error.t) result Lwt.t =
  Lwt.return
    (match id with
    | 1 -> Ok "one"
    | _ -> Error (Forge.Error.not_found "secret"))
[@@get ":id"] [@@intercept [ hidden; counted ]]

let slow () : string Lwt.t =
  let%lwt () = Lwt_unix.sleep 1.0 in
  Lwt.return "late"
[@@get "slow"] [@@intercept [ Forge.Interceptor.timeout 0.05 ]]
```

Interceptor не видит сериализованный ответ и не может сломать тип результата. То, что в Nest делают над готовым ответом (обёртка `{ data }`, кэш ответа, заголовки), — `Dream.middleware`:

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

## Повтор

Spring Retry: `@Retryable(maxAttempts = 3, backoff = @Backoff(100))` на методе сервиса. Forge: `[@@retry n]` на любой функции — в сервисе, в хендлере, где угодно. ppx оборачивает тело в `Forge.Retry.run`: если вызов бросил исключение, он повторяется, всего до `n` раз; `[@@backoff s]` — первая пауза в секундах, дальше вдвое больше. После последней попытки исключение уходит дальше как было.

<!-- $MDX skip -->
```ocaml
let rate ~currency () : float Lwt.t = Exchange_api.rate currency
[@@retry 3] [@@backoff 0.1]
```

Повторяются только исключения. `Error` в `result` — ответ по делу (404, 409), повтор его не исправит. Без ppx — `Forge.Retry.run ~attempts:3 (fun () -> …)`.

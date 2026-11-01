# Interceptors

In Kre an interceptor, `Kre.Interceptor.t`, is a polymorphic function around the **typed** result of a handler; it runs after guards and around parameter parsing:

```ocaml
type t = { around : 'a. Dream.request -> (unit -> ('a, Error.t) result Lwt.t) -> ('a, Error.t) result Lwt.t }
```
```mdx-error
Line 1, characters 25-30:
Error: Unbound module Dream
```

Attaching: `[@@intercept [ … ]]` on a handler, `[@@@intercept [ … ]]` on a controller. Built-in: `logging` (method, path, result, time), `timeout s` (504), `map_error f` (exception mapping), `tap f`, `chain`.

<!-- $MDX file=examples/audit_controller.ml -->
```ocaml
[@@@controller "audit"]
[@@@intercept [ Kre.Interceptor.logging ]]

let hidden =
  Kre.Interceptor.map_error (fun (error : Kre.Error.t) ->
      match error.code with
      | "not_found" -> Kre.Error.forbidden "hidden"
      | _ -> error)

let calls = ref 0

let counted =
  Kre.Interceptor.tap (fun _ ->
      incr calls;
      Lwt.return_unit)

let secret ~(id : int) : (string, Kre.Error.t) result Lwt.t =
  Lwt.return
    (match id with 1 -> Ok "one" | _ -> Error (Kre.Error.not_found "secret"))
[@@get ":id"] [@@intercept [ hidden; counted ]]

let slow () : string Lwt.t =
  let%lwt () = Lwt_unix.sleep 1.0 in
  Lwt.return "late"
[@@get "slow"] [@@intercept [ Kre.Interceptor.timeout 0.05 ]]
```

An interceptor does not see the serialized response and cannot break the result type. Work on the finished response (a `{ data }` wrapper, response caching, headers) is a `Dream.middleware`:

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

## Retry

`[@@retry n]` goes on any function: in a service, in a handler, anywhere. The ppx wraps the body in `Kre.Retry.run`: if the call raised an exception, it is repeated, up to `n` times in total; `[@@backoff s]` is the first pause in seconds, and each next one is twice as long. After the last attempt the exception propagates unchanged.

<!-- $MDX skip -->
```ocaml
let rate ~currency () : float Lwt.t = Exchange_api.rate currency
[@@retry 3] [@@backoff 0.1]
```

Only exceptions are retried. An `Error` in a `result` is a legitimate answer (404, 409); retrying will not fix it. Without the ppx: `Kre.Retry.run ~attempts:3 (fun () -> …)`.

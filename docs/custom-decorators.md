# Custom decorators

Nest: `createParamDecorator` and the built-in `@Req`, `@Ip`, `@Headers`. Kre: any `'a Kre.Guard.t` attached to a parameter through `[@from]` (a synonym of `[@guard]`). The parameter can be positional, as in Nest.

<!-- $MDX file=examples/decorators.ml -->
```ocaml
let client : string Kre.Guard.t =
 fun request -> Lwt.return_ok (Dream.client request)

let language : string Kre.Guard.t =
 fun request ->
  Lwt.return_ok
    (Option.value (Dream.header request "Accept-Language") ~default:"en")
```

<!-- $MDX file=examples/whoami_controller.ml -->
```ocaml
[@@@controller "whoami"]

let show (client : (string[@from Decorators.client]))
    ~(language : (string[@from Decorators.language])) () : string Lwt.t =
  Lwt.return (client ^ " " ^ language)
[@@get]
```

The raw request is a positional `(req : Dream.request)`. There is no counterpart of `@Res()`: the response is the return value.

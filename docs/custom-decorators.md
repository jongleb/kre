# Custom decorators

In Kre a parameter decorator is any `'a Kre.Guard.t` attached to a parameter through `[@from]` (a synonym of `[@guard]`). The parameter can be labeled or positional.

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

The raw request is a positional `(req : Dream.request)`. There is no response parameter: the response is the return value.

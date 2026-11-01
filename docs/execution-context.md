# Execution context

In Kre guards and middleware get the `Dream.request`, which holds the method, path, headers and fields (`Dream.field`). A handler gets it as the positional parameter `(req : Dream.request)`.

<!-- $MDX file=examples/decorators.ml -->
```ocaml
let client : string Kre.Guard.t =
 fun request -> Lwt.return_ok (Dream.client request)

let language : string Kre.Guard.t =
 fun request ->
  Lwt.return_ok
    (Option.value (Dream.header request "Accept-Language") ~default:"en")
```


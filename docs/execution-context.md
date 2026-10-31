# Execution context

Nest: `ExecutionContext` в guards и interceptors. Forge: guard и middleware получают `Dream.request` — в нём метод, путь, заголовки, поля (`Dream.field`). Хендлер получает его позиционным параметром `(req : Dream.request)`.

<!-- $MDX file=examples/decorators.ml -->
```ocaml
let client : string Forge.Guard.t =
 fun request -> Lwt.return_ok (Dream.client request)

let language : string Forge.Guard.t =
 fun request ->
  Lwt.return_ok
    (Option.value (Dream.header request "Accept-Language") ~default:"en")
```


# Custom decorators

Nest: `createParamDecorator` и встроенные `@Req`, `@Ip`, `@Headers`. Kre: любой `'a Kre.Guard.t`, подключённый к параметру через `[@from]` (синоним `[@guard]`). Параметр может быть позиционным, как в Nest.

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

Сырой запрос — позиционный `(req : Dream.request)`. Аналога `@Res()` нет: ответ — это возвращаемое значение.

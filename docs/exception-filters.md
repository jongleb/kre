# Exception filters

Nest: `HttpException` и фильтры. Kre: значение `Kre.Error.t` — статус (только 4xx/5xx), код, текст, расширения — сериализуется как RFC 9457 Problem Details (`application/problem+json`). Хендлер возвращает `(_, Kre.Error.t) result` или вызывает `Kre.Error.fail`; любое другое исключение превращается в 500 с записью в лог.

```json
{ "type": "urn:kre:error:not_found", "title": "Not Found", "status": 404,
  "detail": "cat", "instance": "/cats/7" }
```

Фильтр — `error_handler`, функция от запроса и ошибки к ответу:

<!-- $MDX file=examples/error_pages.ml -->
```ocaml
let handler : Kre.Error.handler =
 fun request error ->
  match error.code with
  | "not_found" -> Dream.html ~status:`Not_Found "<h1>Nothing here</h1>"
  | _ -> Kre.Error.to_response request error
```

Подключение: `Kre.App.run ~error_handler:Error_pages.handler …`.

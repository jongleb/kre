# Exception filters

In Kre an error is a `Kre.Error.t` value (status (4xx/5xx only), code, text, extensions), serialized as RFC 9457 Problem Details (`application/problem+json`). A handler returns `(_, Kre.Error.t) result` or calls `Kre.Error.fail`; any other exception becomes a 500 with a log entry.

```json
{ "type": "urn:kre:error:not_found", "title": "Not Found", "status": 404,
  "detail": "cat", "instance": "/cats/7" }
```

A filter is an `error_handler`, a function from a request and an error to a response:

<!-- $MDX file=examples/error_pages.ml -->
```ocaml
let handler : Kre.Error.handler =
 fun request error ->
  match error.code with
  | "not_found" -> Dream.html ~status:`Not_Found "<h1>Nothing here</h1>"
  | _ -> Kre.Error.to_response request error
```

Wiring: `Kre.App.run ~error_handler:Error_pages.handler …`.

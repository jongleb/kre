# Middleware

Middleware in Kre is `Dream.middleware`; Kre adds nothing of its own.

<!-- $MDX file=../examples/cats/server/logger_middleware.ml -->
```ocaml
let use : Dream.middleware =
 fun next request ->
  Dream.log "Request...";
  next request
```

Where to mount: globally with `Kre.App.run ~middleware`, per controller with `[@@@use [ Logger_middleware.use ]]` (see [Controllers](controllers.md)), per handler with `[@@use [ … ]]`. Order: global → controller → handler middleware → guards → parameter parsing → handler.

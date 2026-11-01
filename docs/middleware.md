# Middleware

Nest: класс `NestMiddleware` и `MiddlewareConsumer.forRoutes`. Kre: `Dream.middleware`, ничего своего.

<!-- $MDX file=../examples/cats/server/logger_middleware.ml -->
```ocaml
let use : Dream.middleware =
 fun next request ->
  Dream.log "Request...";
  next request
```

Где подключать: глобально — `Kre.App.run ~middleware`, на контроллер — `[@@@use [ Logger_middleware.use ]]` (см. [Controllers](controllers.md)), на хендлер — `[@@use [ … ]]`. Порядок: глобальные → контроллерные → хендлерные → guards → разбор параметров → хендлер.

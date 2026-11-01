# Lifecycle events

Nest: `onModuleInit`, `onApplicationShutdown`. Kre: `Kre.App.run ~on_start ~on_shutdown`: `on_start` выполняется до приёма запросов, `on_shutdown` — после остановки по SIGINT/SIGTERM.

<!-- $MDX file=examples/lifecycle.ml -->
```ocaml
let main () =
  Kre.App.run
    ~on_start:(fun () ->
      Dream.log "warming caches";
      Lwt.return_unit)
    ~on_shutdown:(fun () ->
      Dream.log "flushing";
      Lwt.return_unit)
    [ Cats_controller.register (module Cats_service) ]
```


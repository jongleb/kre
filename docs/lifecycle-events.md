# Lifecycle events

Kre has two lifecycle hooks, `Kre.App.run ~on_start ~on_shutdown`: `on_start` runs before requests are accepted, `on_shutdown` runs after stopping on SIGINT/SIGTERM.

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


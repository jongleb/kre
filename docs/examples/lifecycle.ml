let main () =
  Forge.App.run
    ~on_start:(fun () ->
      Dream.log "warming caches";
      Lwt.return_unit)
    ~on_shutdown:(fun () ->
      Dream.log "flushing";
      Lwt.return_unit)
    [ Cats_controller.register (module Cats_service) ]

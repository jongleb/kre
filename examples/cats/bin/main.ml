let () =
  Forge.App.run ~port:8080 ~middleware:[ Dream.logger ]
    [ Cats_controller.register (module Cats_service) ]

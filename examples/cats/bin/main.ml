let () =
  let config = Config.load_exn ~env:(Forge.Config.profile ()) () in
  Format.printf "%a@." Config.pp config;
  Forge.App.run ~port:config.port ~middleware:[ Dream.logger ]
    [ Cats_controller.register (module Cats_service) ]

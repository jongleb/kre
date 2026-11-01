let () =
  let app = [%wire] in
  let actuator =
    Forge.Actuator.make ~checks:app.health
      ~env:(Config.pairs Settings.config)
      app.controllers
  in
  Forge.App.run ~interface:Settings.config.interface ~port:Settings.config.port
    ~middleware:[ Dream.logger; actuator.metrics ]
    ~on_start:app.on_start ~on_shutdown:app.on_shutdown
    (actuator.controller :: Forge.Live.controller :: app.controllers)

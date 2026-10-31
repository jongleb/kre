let () =
  let app = [%wire] in
  let actuator =
    Forge.Actuator.make ~checks:app.health
      ~env:(Config.pairs Settings.config)
      app.controllers
  in
  Forge.App.run ~port:Settings.config.port
    ~middleware:
      [ Dream.logger; actuator.metrics; Web.use ~dir:Settings.config.web ]
    ~on_start:app.on_start ~on_shutdown:app.on_shutdown
    (actuator.controller :: Forge.Live.controller :: app.controllers)

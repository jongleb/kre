let () =
  let app = [%wire] in
  let actuator =
    Forge.Actuator.make ~checks:app.health ~beans:app.beans
      ~env:(Config.pairs Settings.config)
      app.controllers
  in
  Forge.App.run ~interface:Settings.config.interface ~port:Settings.config.port
    ~middleware:[ Dream.logger; Forge.Profiler.middleware; actuator.metrics ]
    ~on_start:app.on_start ~on_shutdown:app.on_shutdown ~commands:app.commands
    (actuator.controller :: Forge.Live.controller :: Forge.Profiler.controller
   :: Mail.controller :: app.controllers)

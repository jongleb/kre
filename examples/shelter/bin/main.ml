let () =
  let app = [%wire] in
  let actuator =
    Kre.Actuator.make ~checks:app.health ~beans:app.beans
      ~env:(Config.pairs Settings.config)
      app.controllers
  in
  Kre.App.run ~interface:Settings.config.interface ~port:Settings.config.port
    ~middleware:[ Dream.logger; Kre.Profiler.middleware; actuator.metrics ]
    ~on_start:app.on_start ~on_shutdown:app.on_shutdown ~commands:app.commands
    (actuator.controller :: Kre.Live.controller :: Kre.Profiler.controller
   :: Mail.controller :: app.controllers)

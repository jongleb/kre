let () =
  let app = [%wire] in
  let actuator =
    Kre.Actuator.make ~checks:app.health ~beans:app.beans
      ~env:(Config.pairs Settings.config)
      app.controllers
  in
  Kre.App.run ~port:Settings.config.port
    ~middleware:
      [ Dream.logger; actuator.metrics; Web.use ~dir:Settings.config.web ]
    ~on_start:app.on_start ~on_shutdown:app.on_shutdown
    (actuator.controller :: Kre.Live.controller :: app.controllers)

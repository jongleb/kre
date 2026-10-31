let () =
  let app =
    [%wire
      "../server";
      "../db"]
  in
  Forge.App.run ~port:Settings.config.port
    ~middleware:[ Dream.logger; Web.use ~dir:Settings.config.web ]
    ~on_start:app.on_start ~on_shutdown:app.on_shutdown app.controllers

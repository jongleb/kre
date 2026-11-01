let () =
  let app = [%wire] in
  Kre.App.run ~on_start:app.on_start ~on_shutdown:app.on_shutdown
    app.controllers

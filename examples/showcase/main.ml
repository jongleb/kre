let controllers =
  [
    Kre.Live.controller;
    Cats_controller.register (module Cats_service);
    Admin_controller.register (module Fake_cats);
    Notes_controller.register ();
    Session_controller.register ();
    Entities_controller.register ();
    Whoami_controller.register ();
    Trace_controller.register ();
    Audit_controller.register ();
    Legacy_controller.register ();
    Ticks_controller.register ();
    Files_controller.register ();
    Tenant_controller.register ();
    Stats_controller.register ();
    Chat_gateway.register ();
  ]

let () =
  Kre.App.run
    ~middleware:
      [
        Dream.logger;
        Kre.Secure_headers.middleware ();
        Kre.Cors.middleware ();
        Kre.Rate_limit.middleware ~limit:600 ~window:60. ();
      ]
    ~error_handler:Error_pages.handler controllers

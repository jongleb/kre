let () =
  Ppxlib.Driver.register_transformation "forge.controller"
    ~impl:Controller.transform

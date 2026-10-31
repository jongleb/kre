let () =
  Ppxlib.Driver.register_transformation "forge.dto"
    ~preprocess_impl:Dto.structure ~preprocess_intf:Dto.signature;
  Ppxlib.Driver.register_transformation "forge.controller"
    ~impl:Controller.transform

let () =
  Ppxlib.Driver.register_transformation "forge.dto"
    ~preprocess_impl:Dto.structure ~preprocess_intf:Dto.signature;
  Ppxlib.Driver.register_transformation "forge.controller"
    ~impl:Controller.transform;
  ignore
    (Ppxlib.Deriving.add "config"
       ~str_type_decl:
         (Ppxlib.Deriving.Generator.V2.make_noarg Configuration.structure)
       ~sig_type_decl:
         (Ppxlib.Deriving.Generator.V2.make_noarg Configuration.signature))

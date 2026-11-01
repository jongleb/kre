let () =
  Ppxlib.Driver.register_transformation "forge.preprocess"
    ~preprocess_impl:(fun items ->
      Dto.structure (Command.structure (Retry.structure items)))
    ~preprocess_intf:Dto.signature;
  Ppxlib.Driver.register_transformation "forge.controller"
    ~impl:Controller.transform;
  Ppxlib.Driver.register_transformation "forge.gateway" ~impl:Gateway.transform;
  Ppxlib.Driver.register_transformation "forge.path"
    ~rules:
      [
        Ppxlib.Context_free.Rule.extension Page.path;
        Ppxlib.Context_free.Rule.extension Wire.extension;
        Ppxlib.Context_free.Rule.extension Embed.extension;
        Ppxlib.Context_free.Rule.extension Http_client.extension;
      ];
  ignore
    (Ppxlib.Deriving.add "config"
       ~str_type_decl:
         (Ppxlib.Deriving.Generator.V2.make_noarg Configuration.structure)
       ~sig_type_decl:
         (Ppxlib.Deriving.Generator.V2.make_noarg Configuration.signature));
  ignore
    (Ppxlib.Deriving.add "params"
       ~str_type_decl:
         (Ppxlib.Deriving.Generator.V2.make
            Ppxlib.Deriving.Args.(empty +> arg "path" (estring __))
            Page.params));
  ignore
    (Ppxlib.Deriving.add "workflow"
       ~str_type_decl:
         (Ppxlib.Deriving.Generator.V2.make_noarg Workflow.structure));
  ignore
    (Ppxlib.Deriving.add "search"
       ~str_type_decl:(Ppxlib.Deriving.Generator.V2.make_noarg Page.search))

let () =
  Ppxlib.Driver.add_arg "-melange"
    (Arg.Unit (fun () -> Table.target := Table.Melange))
    ~doc:" Build for Melange: [@@deriving table] emits nothing";
  ignore
    (Ppxlib.Deriving.add "table"
       ~str_type_decl:
         (Ppxlib.Deriving.Generator.V2.make
            Ppxlib.Deriving.Args.(empty +> arg "name" (estring __))
            Table.structure))

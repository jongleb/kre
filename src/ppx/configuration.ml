open Ppxlib
open Ast_builder.Default

let record ~loc declarations =
  match declarations with
  | [ { ptype_name = { txt = "t"; _ }; ptype_kind = Ptype_record labels; _ } ]
    ->
      labels
  | _ ->
      Location.raise_errorf ~loc
        "[@@@@deriving config] works on one record type named t"

let structure ~ctxt (_, declarations) =
  let loc = Expansion_context.Deriver.derived_item_loc ctxt in
  let named name (label : label_declaration) =
    List.find_opt
      (fun (attribute : attribute) -> String.equal attribute.attr_name.txt name)
      label.pld_attributes
  in
  let payload name label =
    Option.map
      (fun (attribute : attribute) ->
        match attribute.attr_payload with
        | PStr [ { pstr_desc = Pstr_eval (expression, _); _ } ] -> expression
        | _ ->
            Location.raise_errorf ~loc:attribute.attr_loc
              "[@@%s] expects an expression" name)
      (named name label)
  in
  let string_literal (expression : expression) =
    match expression.pexp_desc with
    | Pexp_constant (Pconst_string (s, _, _)) -> s
    | _ ->
        Location.raise_errorf ~loc:expression.pexp_loc
          "expected a string literal"
  in
  let scalar (type_ : core_type) =
    let ident path = pmod_ident ~loc { txt = Longident.parse path; loc } in
    match type_.ptyp_desc with
    | Ptyp_constr ({ txt = Lident "int"; _ }, []) ->
        ident "Forge_shared.Scalar.Int"
    | Ptyp_constr ({ txt = Lident "int64"; _ }, []) ->
        ident "Forge_shared.Scalar.Int64"
    | Ptyp_constr ({ txt = Lident "float"; _ }, []) ->
        ident "Forge_shared.Scalar.Float"
    | Ptyp_constr ({ txt = Lident "string"; _ }, []) ->
        ident "Forge_shared.Scalar.String"
    | Ptyp_constr ({ txt = Lident "bool"; _ }, []) -> ident "Forge.Config.Flag"
    | Ptyp_constr ({ txt = Ldot (path, "t"); loc }, []) ->
        pmod_ident ~loc { txt = path; loc }
    | _ ->
        Location.raise_errorf ~loc:type_.ptyp_loc
          "unsupported config type %a; use int, int64, float, bool, string, \
           T.t with T : Forge_shared.Scalar.S, an option or a list of those"
          Pprintast.core_type type_
  in
  let labels = record ~loc declarations in
  let field_variable (label : label_declaration) =
    "__forge_config_" ^ label.pld_name.txt
  in
  let fields =
    List.map
      (fun (label : label_declaration) ->
        let loc = label.pld_loc in
        let name =
          estring ~loc
            (Option.fold
               ~none:(String.uppercase_ascii label.pld_name.txt)
               ~some:string_literal (payload "env" label))
        in
        let default = payload "default" label in
        let field =
          match (label.pld_type.ptyp_desc, default, payload "sep" label) with
          | Ptyp_constr ({ txt = Lident "option"; _ }, [ _ ]), Some default, _
            ->
              Location.raise_errorf ~loc:default.pexp_loc
                "option field %s cannot have [@@default]: absence is None"
                label.pld_name.txt
          | Ptyp_constr ({ txt = Lident "option"; _ }, [ element ]), None, _ ->
              [%expr
                Forge.Config.field [%e name]
                  [%e pexp_pack ~loc (scalar element)]
                  Forge.Config.Optional]
          | ( Ptyp_constr ({ txt = Lident "list"; _ }, [ element ]),
              _,
              Some separator ) -> (
              match string_literal separator with
              | separator when String.length separator = 1 ->
                  [%expr
                    Forge.Config.list [%e name]
                      ~separator:[%e echar ~loc separator.[0]]
                      [%e pexp_pack ~loc (scalar element)]
                      [%e
                        Option.fold ~none:[%expr Forge.Config.Required]
                          ~some:(fun default ->
                            [%expr Forge.Config.Default [%e default]])
                          default]]
              | _ ->
                  Location.raise_errorf ~loc:separator.pexp_loc
                    "[@@sep] takes one character, e.g. [@@sep \",\"]")
          | Ptyp_constr ({ txt = Lident "list"; _ }, [ _ ]), _, None ->
              Location.raise_errorf ~loc
                "list field %s needs a separator: [@@sep \",\"]"
                label.pld_name.txt
          | _, _, _ ->
              [%expr
                Forge.Config.field [%e name]
                  [%e pexp_pack ~loc (scalar label.pld_type)]
                  [%e
                    Option.fold ~none:[%expr Forge.Config.Required]
                      ~some:(fun default ->
                        [%expr Forge.Config.Default [%e default]])
                      default]]
        in
        [%stri
          let [%p pvar ~loc (field_variable label)] =
            [%e
              Option.fold ~none:field
                ~some:(fun _ -> [%expr Forge.Config.secret [%e field]])
                (named "secret" label)]])
      labels
  in
  let binding (label : label_declaration) =
    binding_op ~loc ~op:{ txt = "let+"; loc }
      ~pat:(pvar ~loc ("__forge_" ^ label.pld_name.txt))
      ~exp:[%expr Forge.Config.read env [%e evar ~loc (field_variable label)]]
  in
  let load =
    match labels with
    | [] -> Location.raise_errorf ~loc "[@@@@deriving config] needs fields"
    | first :: rest ->
        [%stri
          let load ?(env = Sys.getenv_opt) () =
            let open Forge.Config.Syntax in
            [%e
              pexp_letop ~loc
                (letop ~let_:(binding first)
                   ~ands:
                     (List.map
                        (fun label ->
                          {
                            (binding label) with
                            pbop_op = { txt = "and+"; loc };
                          })
                        rest)
                   ~body:
                     (pexp_record ~loc
                        (List.map
                           (fun (label : label_declaration) ->
                             ( { txt = Lident label.pld_name.txt; loc },
                               evar ~loc ("__forge_" ^ label.pld_name.txt) ))
                           labels)
                        None))]]
  in
  fields
  @ [
      load;
      [%stri let load_exn ?env () = Forge.Config.exit_on_error (load ?env ())];
      [%stri
        let pairs (config : t) =
          [%e
            elist ~loc
              (List.map
                 (fun (label : label_declaration) ->
                   [%expr
                     Forge.Config.show
                       [%e evar ~loc (field_variable label)]
                       [%e
                         pexp_field ~loc [%expr config]
                           { txt = Lident label.pld_name.txt; loc }]])
                 labels)]];
      [%stri let pp ppf config = Forge.Config.pp ppf (pairs config)];
    ]

let signature ~ctxt (_, declarations) =
  let loc = Expansion_context.Deriver.derived_item_loc ctxt in
  ignore (record ~loc declarations);
  [
    [%sigi: val load : ?env:Forge.Config.env -> unit -> (t, string list) result];
    [%sigi: val load_exn : ?env:Forge.Config.env -> unit -> t];
    [%sigi: val pairs : t -> (string * string) list];
    [%sigi: val pp : Format.formatter -> t -> unit];
  ]

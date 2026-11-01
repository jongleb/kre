open Ppxlib
open Ast_builder.Default

let record ~loc ~deriver (declarations : type_declaration list) =
  match declarations with
  | [ ({ ptype_kind = Ptype_record labels; _ } as declaration) ] ->
      (declaration.ptype_name.txt, labels)
  | _ ->
      Location.raise_errorf ~loc "[@@@@deriving %s] works on one record type"
        deriver

let value_name type_name suffix =
  match type_name with "t" -> suffix | name -> name ^ "_" ^ suffix

let scalar (type_ : core_type) =
  let loc = type_.ptyp_loc in
  let ident path = pmod_ident ~loc { txt = Longident.parse path; loc } in
  match type_.ptyp_desc with
  | Ptyp_constr ({ txt = Lident "int"; _ }, []) -> ident "Kre_shared.Scalar.Int"
  | Ptyp_constr ({ txt = Lident "int64"; _ }, []) ->
      ident "Kre_shared.Scalar.Int64"
  | Ptyp_constr ({ txt = Lident "float"; _ }, []) ->
      ident "Kre_shared.Scalar.Float"
  | Ptyp_constr ({ txt = Lident "bool"; _ }, []) ->
      ident "Kre_shared.Scalar.Bool"
  | Ptyp_constr ({ txt = Lident "string"; _ }, []) ->
      ident "Kre_shared.Scalar.String"
  | Ptyp_constr ({ txt = Ldot (path, "t"); loc }, []) ->
      pmod_ident ~loc { txt = path; loc }
  | _ ->
      Location.raise_errorf ~loc
        "unsupported type %a; use int, int64, float, bool, string or T.t with \
         T : Kre_shared.Scalar.S"
        Pprintast.core_type type_

let applicative ~loc ~read labels =
  let binding (label : label_declaration) =
    binding_op ~loc ~op:{ txt = "let+"; loc }
      ~pat:(pvar ~loc ("__kre_" ^ label.pld_name.txt))
      ~exp:(read label)
  in
  match labels with
  | [] -> Location.raise_errorf ~loc "the record needs at least one field"
  | first :: rest ->
      [%expr
        let open Kre_shared.Validation.Syntax in
        [%e
          pexp_letop ~loc
            (letop ~let_:(binding first)
               ~ands:
                 (List.map
                    (fun label ->
                      { (binding label) with pbop_op = { txt = "and+"; loc } })
                    rest)
               ~body:
                 (pexp_record ~loc
                    (List.map
                       (fun (label : label_declaration) ->
                         ( { txt = Lident label.pld_name.txt; loc },
                           evar ~loc ("__kre_" ^ label.pld_name.txt) ))
                       labels)
                    None))]]

let field ~loc record (label : label_declaration) =
  pexp_field ~loc (evar ~loc record) { txt = Lident label.pld_name.txt; loc }

let params ~ctxt (_, declarations) path =
  let loc = Expansion_context.Deriver.derived_item_loc ctxt in
  let name, labels = record ~loc ~deriver:"params" declarations in
  let pattern =
    match path with
    | Some pattern -> pattern
    | None ->
        Location.raise_errorf ~loc
          "[@@@@deriving params] needs its page path: [@@@@deriving params \
           ~path:\"/cats/:id\"]"
  in
  let segments =
    List.filter_map
      (fun segment ->
        match String.split_on_char ':' segment with
        | [ ""; name ] -> Some name
        | _ -> None)
      (String.split_on_char '/' pattern)
  in
  let fields =
    List.map (fun (label : label_declaration) -> label.pld_name.txt) labels
  in
  let missing names known =
    List.filter (fun name -> not (List.mem name known)) names
  in
  (match (missing segments fields, missing fields segments) with
  | [], [] -> ()
  | unbound, unused ->
      Location.raise_errorf ~loc
        "path %s and the record disagree: segments without a field: [%s]; \
         fields without a segment: [%s]"
        pattern
        (String.concat "; " unbound)
        (String.concat "; " unused));
  [
    [%stri
      let [%p pvar ~loc (value_name name "path")] :
          [%t ptyp_constr ~loc { txt = Lident name; loc } []] Kre_client.Path.t
          =
        Kre_client.Path.make [%e estring ~loc pattern]
          ~decode:(fun __kre_pairs ->
            [%e
              applicative ~loc labels ~read:(fun label ->
                  [%expr
                    Kre_client.Path.param
                      [%e pexp_pack ~loc (scalar label.pld_type)]
                      [%e estring ~loc label.pld_name.txt]
                      __kre_pairs])])
          ~encode:(fun __kre_params ->
            [%e
              elist ~loc
                (List.map
                   (fun (label : label_declaration) ->
                     [%expr
                       [%e estring ~loc label.pld_name.txt],
                       let module M = [%m scalar label.pld_type] in
                       M.to_string [%e field ~loc "__kre_params" label]])
                   labels)])];
  ]

let search ~ctxt (_, declarations) =
  let loc = Expansion_context.Deriver.derived_item_loc ctxt in
  let name, labels = record ~loc ~deriver:"search" declarations in
  let variable (label : label_declaration) =
    "__kre_field_" ^ label.pld_name.txt
  in
  let fields =
    List.map
      (fun (label : label_declaration) ->
        let loc = label.pld_loc in
        let default =
          List.find_map
            (fun (attribute : attribute) ->
              match (attribute.attr_name.txt, attribute.attr_payload) with
              | "default", PStr [ { pstr_desc = Pstr_eval (default, _); _ } ] ->
                  Some default
              | _ -> None)
            label.pld_attributes
        in
        let presence, element =
          match (label.pld_type.ptyp_desc, default) with
          | ( Ptyp_constr ({ txt = Lident ("option" | "list"); _ }, [ _ ]),
              Some default ) ->
              Location.raise_errorf ~loc:default.pexp_loc
                "%s cannot have [@@default]: an absent option is None, an \
                 absent list is []"
                label.pld_name.txt
          | Ptyp_constr ({ txt = Lident "option"; _ }, [ element ]), None ->
              ([%expr Kre_shared.Search.Optional], element)
          | Ptyp_constr ({ txt = Lident "list"; _ }, [ element ]), None ->
              ([%expr Kre_shared.Search.Repeated], element)
          | _, Some default ->
              ([%expr Kre_shared.Search.Default [%e default]], label.pld_type)
          | _, None -> ([%expr Kre_shared.Search.Required], label.pld_type)
        in
        value_binding ~loc
          ~pat:(pvar ~loc (variable label))
          ~expr:
            [%expr
              Kre_shared.Search.field
                [%e estring ~loc label.pld_name.txt]
                [%e pexp_pack ~loc (scalar element)]
                [%e presence]])
      labels
  in
  [
    [%stri
      let [%p pvar ~loc (value_name name "codec")] :
          [%t ptyp_constr ~loc { txt = Lident name; loc } []]
          Kre_shared.Search.t =
        [%e
          pexp_let ~loc Nonrecursive fields
            [%expr
              Kre_shared.Search.make
                ~parse:(fun __kre_pairs ->
                  [%e
                    applicative ~loc labels ~read:(fun label ->
                        [%expr
                          Kre_shared.Search.read
                            [%e evar ~loc (variable label)]
                            __kre_pairs])])
                ~print:(fun __kre_search ->
                  [%e
                    elist ~loc
                      (List.map
                         (fun label ->
                           [%expr
                             Kre_shared.Search.show
                               [%e evar ~loc (variable label)]
                               [%e field ~loc "__kre_search" label]])
                         labels)])]]];
  ]

let path =
  Extension.V3.declare "path" Extension.Context.expression
    Ast_pattern.(single_expr_payload (estring __))
    (fun ~ctxt pattern ->
      let loc = Expansion_context.Extension.extension_point_loc ctxt in
      match String.index_opt pattern ':' with
      | Some _ ->
          Location.raise_errorf ~loc
            "[%%path %S] has parameters; declare them with type params = { … } \
             [@@@@deriving params ~path:%S]"
            pattern pattern
      | None -> [%expr Kre_client.Path.static [%e estring ~loc pattern]])

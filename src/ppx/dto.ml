open Ppxlib
open Ast_builder.Default

(** [Strict] rejects unknown JSON fields. *)
type strictness = Strict | Lenient

type checked = { field : string; key : string; rules : expression list }
(** A record field with [[@validate]] rules and its JSON key. *)

let rewrite (declaration : type_declaration) =
  let loc = declaration.ptype_loc in
  let derivers (attribute : attribute) =
    match attribute.attr_payload with
    | PStr [ { pstr_desc = Pstr_eval (payload, _); _ } ] -> (
        match payload.pexp_desc with
        | Pexp_tuple items -> items
        | _ -> [ payload ])
    | _ -> []
  in
  let dto (deriver : expression) =
    match deriver.pexp_desc with
    | Pexp_ident { txt = Lident "dto"; _ } -> Some Lenient
    | Pexp_apply
        ({ pexp_desc = Pexp_ident { txt = Lident "dto"; _ }; _ }, options) ->
        Some
          (List.fold_left
             (fun _ (label, (option : expression)) ->
               match label with
               | Labelled "strict" -> Strict
               | _ ->
                   Location.raise_errorf ~loc:option.pexp_loc
                     "[@@@@deriving dto] takes only ~strict; ~partial_of, \
                      ~pick_of and ~omit_of come in phase 2")
             Lenient options)
    | _ -> None
  in
  let rewritten =
    List.map
      (fun (attribute : attribute) ->
        match attribute.attr_name.txt with
        | "deriving" ->
            Option.fold ~none:(attribute, None)
              ~some:(fun strictness ->
                ( {
                    attribute with
                    attr_payload =
                      PStr
                        [
                          pstr_eval ~loc
                            (pexp_tuple ~loc
                               (List.concat_map
                                  (fun deriver ->
                                    Option.fold ~none:[ deriver ]
                                      ~some:(fun _ ->
                                        [
                                          evar ~loc "json";
                                          evar ~loc "jsonschema";
                                        ])
                                      (dto deriver))
                                  (derivers attribute)))
                            [];
                        ];
                  },
                  Some strictness ))
              (List.find_map dto (derivers attribute))
        | _ -> (attribute, None))
      declaration.ptype_attributes
  in
  Option.fold ~none:(declaration, None)
    ~some:(fun strictness ->
      let string_payload (attribute : attribute) =
        match attribute.attr_payload with
        | PStr
            [
              {
                pstr_desc =
                  Pstr_eval
                    ( { pexp_desc = Pexp_constant (Pconst_string (s, _, _)); _ },
                      _ );
                _;
              };
            ] ->
            s
        | _ ->
            Location.raise_errorf ~loc:attribute.attr_loc
              "[@@%s] expects a string literal" attribute.attr_name.txt
      in
      let expression_payload (attribute : attribute) =
        match attribute.attr_payload with
        | PStr [ { pstr_desc = Pstr_eval (expression, _); _ } ] -> expression
        | _ ->
            Location.raise_errorf ~loc:attribute.attr_loc
              "[@@%s] expects an expression, e.g. [@@validate max_length 16]"
              attribute.attr_name.txt
      in
      let labels =
        match declaration.ptype_kind with
        | Ptype_record labels -> labels
        | _ -> []
      in
      let checked =
        List.filter_map
          (fun (label : label_declaration) ->
            match
              List.concat_map
                (fun (attribute : attribute) ->
                  match attribute.attr_name.txt with
                  | "validate" ->
                      let rec sequence (expression : expression) =
                        match expression.pexp_desc with
                        | Pexp_sequence (first, rest) -> first :: sequence rest
                        | _ -> [ expression ]
                      in
                      List.map
                        (fun rule ->
                          [%expr Forge_shared.Validation.([%e rule])])
                        (sequence (expression_payload attribute))
                  | "validate.custom" ->
                      [
                        [%expr
                          Forge_shared.Validation.rule ~name:"custom"
                            [%e expression_payload attribute]];
                      ]
                  | _ -> [])
                label.pld_attributes
            with
            | [] -> None
            | rules ->
                Some
                  {
                    field = label.pld_name.txt;
                    key =
                      Option.value ~default:label.pld_name.txt
                        (List.find_map
                           (fun (attribute : attribute) ->
                             match attribute.attr_name.txt with
                             | "key" | "json.key" ->
                                 Some (string_payload attribute)
                             | _ -> None)
                           label.pld_attributes);
                    rules;
                  })
          labels
      in
      let of_json =
        match declaration.ptype_name.txt with
        | "t" -> "of_json"
        | name -> name ^ "_of_json"
      in
      let variable field = "__forge_" ^ field in
      ( {
          declaration with
          ptype_attributes =
            (List.map fst rewritten
            @
            match strictness with
            | Strict ->
                [
                  attribute ~loc
                    ~name:{ txt = "disallow_extra_fields"; loc }
                    ~payload:(PStr []);
                ]
            | Lenient -> []);
        },
        match checked with
        | [] -> None
        | first :: rest ->
            let binding { field; key; rules } =
              binding_op ~loc ~op:{ txt = "let+"; loc }
                ~pat:(pvar ~loc (variable field))
                ~exp:
                  [%expr
                    Forge_shared.Validation.field [%e estring ~loc key]
                      [%e elist ~loc rules]
                      [%e
                        pexp_field ~loc [%expr __forge_value]
                          { txt = Lident field; loc }]]
            in
            Some
              [%stri
                let [%p pvar ~loc of_json] =
                 fun __forge_json ->
                  let __forge_value = [%e evar ~loc of_json] __forge_json in
                  Forge_shared.Validation.ok_exn
                    (let open Forge_shared.Validation.Syntax in
                     [%e
                       pexp_letop ~loc
                         (letop ~let_:(binding first)
                            ~ands:
                              (List.map
                                 (fun checked ->
                                   {
                                     (binding checked) with
                                     pbop_op = { txt = "and+"; loc };
                                   })
                                 rest)
                            ~body:
                              (pexp_record ~loc
                                 (List.map
                                    (fun { field; _ } ->
                                      ( { txt = Lident field; loc },
                                        evar ~loc (variable field) ))
                                    checked)
                                 (match List.compare_lengths checked labels with
                                 | 0 -> None
                                 | _ -> Some [%expr __forge_value])))])] ))
    (List.find_map snd rewritten)

let mapper =
  object
    inherit Ast_traverse.map as super

    method! structure items =
      List.concat_map
        (fun (item : structure_item) ->
          match item.pstr_desc with
          | Pstr_type (flag, declarations) ->
              let rewritten = List.map rewrite declarations in
              { item with pstr_desc = Pstr_type (flag, List.map fst rewritten) }
              :: List.filter_map snd rewritten
          | _ -> [ super#structure_item item ])
        items

    method! signature_item item =
      match item.psig_desc with
      | Psig_type (flag, declarations) ->
          {
            item with
            psig_desc =
              Psig_type
                ( flag,
                  List.map
                    (fun declaration -> fst (rewrite declaration))
                    declarations );
          }
      | _ -> super#signature_item item
  end

let structure items = mapper#structure items
let signature items = mapper#signature items

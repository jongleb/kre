open Ppxlib
open Ast_builder.Default

(** [Strict] rejects unknown JSON fields. *)
type strictness = Strict | Lenient

(** A type built from another record of the same file. *)
type mapped =
  | Partial of string
  | Pick of string * string list
  | Omit of string * string list

type checked = { field : string; key : string; rules : expression list }
(** A record field with [[@validate]] rules and its JSON key. *)

let derivers (attribute : attribute) =
  match attribute.attr_payload with
  | PStr [ { pstr_desc = Pstr_eval (payload, _); _ } ] -> (
      match payload.pexp_desc with
      | Pexp_tuple items -> items
      | _ -> [ payload ])
  | _ -> []

let named type_name suffix =
  match type_name with "t" -> suffix | name -> name ^ "_" ^ suffix

let rewrite ~known (declaration : type_declaration) =
  let loc = declaration.ptype_loc in
  let strings (expression : expression) =
    let rec elements (expression : expression) =
      match expression.pexp_desc with
      | Pexp_construct ({ txt = Lident "[]"; _ }, None) -> []
      | Pexp_construct
          ( { txt = Lident "::"; _ },
            Some
              {
                pexp_desc =
                  Pexp_tuple
                    [
                      { pexp_desc = Pexp_constant (Pconst_string (s, _, _)); _ };
                      tail;
                    ];
                _;
              } ) ->
          s :: elements tail
      | _ ->
          Location.raise_errorf ~loc:expression.pexp_loc
            "expected a list of field names, e.g. [ \"id\"; \"name\" ]"
    in
    elements expression
  in
  let source (expression : expression) =
    match expression.pexp_desc with
    | Pexp_ident { txt = Lident name; _ } -> name
    | _ ->
        Location.raise_errorf ~loc:expression.pexp_loc
          "expected a record type of this file, e.g. ~partial_of:t"
  in
  let options (deriver : expression) =
    match deriver.pexp_desc with
    | Pexp_ident { txt = Lident "dto"; _ } -> Some (Lenient, None)
    | Pexp_apply
        ({ pexp_desc = Pexp_ident { txt = Lident "dto"; _ }; _ }, options) ->
        Some
          (List.fold_left
             (fun (strictness, mapped) (label, (option : expression)) ->
               match (label, option.pexp_desc) with
               | Labelled "strict", _ -> (Strict, mapped)
               | Labelled "partial_of", _ ->
                   (strictness, Some (Partial (source option)))
               | Labelled "pick_of", Pexp_tuple [ from; fields ] ->
                   (strictness, Some (Pick (source from, strings fields)))
               | Labelled "omit_of", Pexp_tuple [ from; fields ] ->
                   (strictness, Some (Omit (source from, strings fields)))
               | _ ->
                   Location.raise_errorf ~loc:option.pexp_loc
                     "[@@@@deriving dto] options: ~strict, ~partial_of:t, \
                      ~pick_of:(t, [ \"id\" ]), ~omit_of:(t, [ \"password\" ])")
             (Lenient, None) options)
    | _ -> None
  in
  let cases =
    match declaration.ptype_kind with
    | Ptype_variant constructors
      when List.for_all
             (fun (constructor : constructor_declaration) ->
               match constructor.pcd_args with
               | Pcstr_tuple [] -> true
               | Pcstr_tuple _ | Pcstr_record _ -> false)
             constructors ->
        Some
          (List.map
             (fun (constructor : constructor_declaration) ->
               ( constructor.pcd_name.txt,
                 Option.value
                   ~default:(String.lowercase_ascii constructor.pcd_name.txt)
                   (List.find_map
                      (fun (attribute : attribute) ->
                        match
                          (attribute.attr_name.txt, attribute.attr_payload)
                        with
                        | ( "key",
                            PStr
                              [
                                {
                                  pstr_desc =
                                    Pstr_eval
                                      ( {
                                          pexp_desc =
                                            Pexp_constant
                                              (Pconst_string (s, _, _));
                                          _;
                                        },
                                        _ );
                                  _;
                                };
                              ] ) ->
                            Some s
                        | _ -> None)
                      constructor.pcd_attributes) ))
             constructors)
    | _ -> None
  in
  let rewritten =
    List.map
      (fun (attribute : attribute) ->
        match attribute.attr_name.txt with
        | "deriving" ->
            Option.fold ~none:(Some attribute, None)
              ~some:(fun found ->
                match
                  List.concat_map
                    (fun deriver ->
                      match (options deriver, cases) with
                      | None, _ -> [ deriver ]
                      | Some _, Some _ -> []
                      | Some _, None ->
                          [ evar ~loc "json"; evar ~loc "jsonschema" ])
                    (derivers attribute)
                with
                | [] -> (None, Some found)
                | kept ->
                    ( Some
                        {
                          attribute with
                          attr_payload =
                            PStr [ pstr_eval ~loc (pexp_tuple ~loc kept) [] ];
                        },
                      Some found ))
              (List.find_map options (derivers attribute))
        | _ -> (Some attribute, None))
      declaration.ptype_attributes
  in
  let found = List.find_map snd rewritten in
  match (cases, found) with
  | Some cases, Some _ ->
      let type_name = declaration.ptype_name.txt in
      let construct name =
        pexp_construct ~loc { txt = Lident name; loc } None
      in
      let values = List.map snd cases in
      ( { declaration with ptype_attributes = List.filter_map fst rewritten },
        [
          [%stri
            let [%p pvar ~loc (named type_name "name")] =
              [%e estring ~loc type_name]];
          [%stri
            let [%p pvar ~loc (named type_name "to_string")] =
              [%e
                pexp_function_cases ~loc
                  (List.map
                     (fun (name, value) ->
                       case
                         ~lhs:
                           (ppat_construct ~loc { txt = Lident name; loc } None)
                         ~guard:None ~rhs:(estring ~loc value))
                     cases)]];
          [%stri
            let [%p pvar ~loc (named type_name "of_string")] =
              [%e
                pexp_function_cases ~loc
                  (List.map
                     (fun (name, value) ->
                       case ~lhs:(pstring ~loc value) ~guard:None
                         ~rhs:[%expr Ok [%e construct name]])
                     cases
                  @ [
                      case
                        ~lhs:[%pat? _]
                        ~guard:None
                        ~rhs:
                          [%expr
                            Error
                              (Kre_shared.Validation.fail ~rule:"one_of"
                                 [%e
                                   estring ~loc
                                     ("must be one of "
                                    ^ String.concat ", " values)])];
                    ])]];
          [%stri
            let [%p pvar ~loc (named type_name "to_json")] =
             fun __kre_value ->
              Jsonkit.declassify
                (`String
                   ([%e evar ~loc (named type_name "to_string")] __kre_value))];
          [%stri
            let [%p pvar ~loc (named type_name "of_json")] =
             fun __kre_json ->
              match Jsonkit.classify __kre_json with
              | `String __kre_string ->
                  Kre_shared.Validation.ok_exn
                    ([%e evar ~loc (named type_name "of_string")] __kre_string)
              | _ ->
                  raise
                    (Kre_shared.Validation.Invalid
                       (Kre_shared.Validation.fail ~rule:"type"
                          "must be a string"))];
          [%stri
            let [%p
                  pvar ~loc
                    (match type_name with
                    | "t" -> "t_jsonschema"
                    | name -> name ^ "_jsonschema")] =
              `Assoc
                [
                  ("type", `String "string");
                  ( "enum",
                    `List
                      [%e
                        elist ~loc
                          (List.map
                             (fun value ->
                               [%expr `String [%e estring ~loc value]])
                             values)] );
                ]];
        ] )
  | (Some _ | None), _ ->
      Option.fold ~none:(declaration, [])
        ~some:(fun (strictness, mapped) ->
          let type_name = declaration.ptype_name.txt in
          let source_labels name =
            match List.assoc_opt name known with
            | Some labels -> labels
            | None ->
                Location.raise_errorf ~loc
                  "%s is not a record type declared earlier in this file" name
          in
          let check_fields name (labels : label_declaration list) fields =
            List.iter
              (fun field ->
                match
                  List.find_opt
                    (fun (label : label_declaration) ->
                      String.equal label.pld_name.txt field)
                    labels
                with
                | Some _ -> ()
                | None ->
                    Location.raise_errorf ~loc "%s has no field %s" name field)
              fields
          in
          let labels =
            match
              (mapped, declaration.ptype_kind, declaration.ptype_manifest)
            with
            | None, Ptype_record labels, _ -> labels
            | None, _, _ -> []
            | Some (Pick (name, fields)), Ptype_abstract, None ->
                let labels = source_labels name in
                check_fields name labels fields;
                List.filter
                  (fun (label : label_declaration) ->
                    List.mem label.pld_name.txt fields)
                  labels
            | Some (Omit (name, fields)), Ptype_abstract, None ->
                let labels = source_labels name in
                check_fields name labels fields;
                List.filter
                  (fun (label : label_declaration) ->
                    not (List.mem label.pld_name.txt fields))
                  labels
            | Some (Partial name), Ptype_abstract, None ->
                List.map
                  (fun (label : label_declaration) ->
                    {
                      label with
                      pld_type =
                        ptyp_constr ~loc:label.pld_loc
                          { txt = Lident "option"; loc = label.pld_loc }
                          [ label.pld_type ];
                      pld_attributes =
                        attribute ~loc:label.pld_loc
                          ~name:{ txt = "option"; loc = label.pld_loc }
                          ~payload:(PStr [])
                        :: List.filter
                             (fun (attribute : attribute) ->
                               List.mem attribute.attr_name.txt
                                 [ "key"; "json.key" ])
                             label.pld_attributes;
                    })
                  (source_labels name)
            | Some _, _, _ ->
                Location.raise_errorf ~loc
                  "a mapped dto is declared abstract: type %s [@@@@deriving \
                   dto ~pick_of:(t, [ \"id\" ])]"
                  type_name
          in
          let attribute_named name (label : label_declaration) =
            List.find_opt
              (fun (attribute : attribute) ->
                String.equal attribute.attr_name.txt name)
              label.pld_attributes
          in
          let expression_payload (attribute : attribute) =
            match attribute.attr_payload with
            | PStr [ { pstr_desc = Pstr_eval (expression, _); _ } ] ->
                expression
            | _ ->
                Location.raise_errorf ~loc:attribute.attr_loc
                  "[@@%s] expects an expression, e.g. [@@validate max_length \
                   16]"
                  attribute.attr_name.txt
          in
          let key (label : label_declaration) =
            Option.value ~default:label.pld_name.txt
              (List.find_map
                 (fun (attribute : attribute) ->
                   match (attribute.attr_name.txt, attribute.attr_payload) with
                   | ( ("key" | "json.key"),
                       PStr
                         [
                           {
                             pstr_desc =
                               Pstr_eval
                                 ( {
                                     pexp_desc =
                                       Pexp_constant (Pconst_string (s, _, _));
                                     _;
                                   },
                                   _ );
                             _;
                           };
                         ] ) ->
                       Some s
                   | _ -> None)
                 label.pld_attributes)
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
                            | Pexp_sequence (first, rest) ->
                                first :: sequence rest
                            | _ -> [ expression ]
                          in
                          List.map
                            (fun rule ->
                              [%expr Kre_shared.Validation.([%e rule])])
                            (sequence (expression_payload attribute))
                      | "validate.custom" ->
                          [
                            [%expr
                              Kre_shared.Validation.rule ~name:"custom"
                                [%e expression_payload attribute]];
                          ]
                      | _ -> [])
                    label.pld_attributes
                with
                | [] -> None
                | rules ->
                    Some { field = label.pld_name.txt; key = key label; rules })
              labels
          in
          let field ~loc record name =
            pexp_field ~loc (evar ~loc record) { txt = Lident name; loc }
          in
          let record fields base =
            pexp_record ~loc
              (List.map
                 (fun (name, value) -> ({ txt = Lident name; loc }, value))
                 fields)
              (match List.compare_lengths fields labels with
              | 0 -> None
              | _ -> Some base)
          in
          let validator =
            match checked with
            | [] -> []
            | first :: rest ->
                let variable field = "__kre_" ^ field in
                let binding { field = name; key; rules } =
                  binding_op ~loc ~op:{ txt = "let+"; loc }
                    ~pat:(pvar ~loc (variable name))
                    ~exp:
                      [%expr
                        Kre_shared.Validation.field [%e estring ~loc key]
                          [%e elist ~loc rules]
                          [%e field ~loc "__kre_value" name]]
                in
                [
                  [%stri
                    let [%p pvar ~loc (named type_name "of_json")] =
                     fun __kre_json ->
                      let __kre_value =
                        [%e evar ~loc (named type_name "of_json")] __kre_json
                      in
                      Kre_shared.Validation.ok_exn
                        (let open Kre_shared.Validation.Syntax in
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
                                  (record
                                     (List.map
                                        (fun { field = name; _ } ->
                                          (name, evar ~loc (variable name)))
                                        checked)
                                     [%expr __kre_value]))])];
                ]
          in
          let excluded =
            List.filter_map
              (fun label ->
                Option.map
                  (fun _ -> key label)
                  (attribute_named "exclude" label))
              labels
          in
          let transformed =
            List.filter_map
              (fun (label : label_declaration) ->
                Option.map
                  (fun attribute ->
                    (label.pld_name.txt, expression_payload attribute))
                  (attribute_named "transform" label))
              labels
          in
          let output =
            match (excluded, transformed) with
            | [], [] -> []
            | _ ->
                let to_json = named type_name "to_json" in
                let schema =
                  match type_name with
                  | "t" -> "t_jsonschema"
                  | name -> name ^ "_jsonschema"
                in
                [%stri
                  let [%p pvar ~loc to_json] =
                   fun (__kre_value :
                         [%t
                           ptyp_constr ~loc { txt = Lident type_name; loc } []]) ->
                    Kre_shared.Json.omit
                      [%e elist ~loc (List.map (estring ~loc) excluded)]
                      ([%e evar ~loc to_json]
                         [%e
                           match transformed with
                           | [] -> [%expr __kre_value]
                           | transformed ->
                               record
                                 (List.map
                                    (fun (name, f) ->
                                      ( name,
                                        [%expr
                                          [%e f]
                                            [%e field ~loc "__kre_value" name]]
                                      ))
                                    transformed)
                                 [%expr __kre_value]])]
                ::
                (match excluded with
                | [] -> []
                | _ ->
                    [
                      [%stri
                        let [%p pvar ~loc schema] =
                          Kre_shared.Json.write_only
                            [%e elist ~loc (List.map (estring ~loc) excluded)]
                            [%e evar ~loc schema]];
                    ])
          in
          let target = ptyp_constr ~loc { txt = Lident type_name; loc } [] in
          let projection =
            match mapped with
            | None -> []
            | Some (Pick (name, _) | Omit (name, _)) ->
                [
                  [%stri
                    let [%p pvar ~loc (type_name ^ "_of_" ^ name)] =
                     fun (__kre_source :
                           [%t ptyp_constr ~loc { txt = Lident name; loc } []])
                         : [%t target] ->
                      [%e
                        record
                          (List.map
                             (fun (label : label_declaration) ->
                               ( label.pld_name.txt,
                                 field ~loc "__kre_source" label.pld_name.txt ))
                             labels)
                          [%expr __kre_source]]];
                ]
            | Some (Partial name) ->
                let source = ptyp_constr ~loc { txt = Lident name; loc } [] in
                [
                  [%stri
                    let [%p pvar ~loc (type_name ^ "_apply")] =
                     fun (__kre_patch : [%t target])
                         (__kre_source : [%t source]) : [%t source] ->
                      [%e
                        record
                          (List.map
                             (fun (label : label_declaration) ->
                               ( label.pld_name.txt,
                                 [%expr
                                   Option.value
                                     [%e
                                       field ~loc "__kre_patch"
                                         label.pld_name.txt]
                                     ~default:
                                       [%e
                                         field ~loc "__kre_source"
                                           label.pld_name.txt]] ))
                             labels)
                          [%expr __kre_source]]];
                ]
          in
          ( {
              declaration with
              ptype_kind =
                (match mapped with
                | None -> declaration.ptype_kind
                | Some _ -> Ptype_record labels);
              ptype_attributes =
                (List.filter_map fst rewritten
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
            validator @ output @ projection ))
        found

let mapper =
  object (self)
    inherit Ast_traverse.map as super

    method! structure items =
      snd
        (List.fold_left
           (fun (known, items) (item : structure_item) ->
             match item.pstr_desc with
             | Pstr_type (flag, declarations) ->
                 let rewritten = List.map (rewrite ~known) declarations in
                 let declarations = List.map fst rewritten in
                 ( known
                   @ List.filter_map
                       (fun (declaration : type_declaration) ->
                         match declaration.ptype_kind with
                         | Ptype_record labels ->
                             Some (declaration.ptype_name.txt, labels)
                         | _ -> None)
                       declarations,
                   items
                   @ { item with pstr_desc = Pstr_type (flag, declarations) }
                     :: List.concat_map snd rewritten )
             | _ -> (known, items @ [ self#structure_item item ]))
           ([], []) items)

    method! signature_item item =
      match item.psig_desc with
      | Psig_type (flag, declarations) ->
          {
            item with
            psig_desc =
              Psig_type
                ( flag,
                  List.map
                    (fun declaration -> fst (rewrite ~known:[] declaration))
                    declarations );
          }
      | _ -> super#signature_item item
  end

let structure items = mapper#structure items
let signature items = mapper#signature items

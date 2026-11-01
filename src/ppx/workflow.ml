open Ppxlib
open Ast_builder.Default

let structure ~ctxt (_, declarations) =
  let loc = Expansion_context.Deriver.derived_item_loc ctxt in
  let declaration, constructors =
    match declarations with
    | [ ({ ptype_kind = Ptype_variant constructors; _ } as declaration) ] ->
        (declaration, constructors)
    | _ ->
        Location.raise_errorf ~loc
          "[@@@@deriving workflow] works on a variant of states"
  in
  let states =
    List.map
      (fun (constructor : constructor_declaration) ->
        match constructor.pcd_args with
        | Pcstr_tuple [] -> constructor.pcd_name.txt
        | Pcstr_tuple _ | Pcstr_record _ ->
            Location.raise_errorf ~loc:constructor.pcd_loc
              "workflow states carry no data; %s has arguments"
              constructor.pcd_name.txt)
      constructors
  in
  let named suffix =
    match declaration.ptype_name.txt with
    | "t" -> suffix
    | name -> name ^ "_" ^ suffix
  in
  let transitions =
    match
      List.find_map
        (fun (attribute : attribute) ->
          match (attribute.attr_name.txt, attribute.attr_payload) with
          | ( "transitions",
              PStr
                [
                  {
                    pstr_desc =
                      Pstr_eval
                        ({ pexp_desc = Pexp_record (fields, None); _ }, _);
                    _;
                  };
                ] ) ->
              Some fields
          | "transitions", _ ->
              Location.raise_errorf ~loc:attribute.attr_loc
                "[@@@@transitions] is a record of functions: [@@@@transitions \
                 { adopt = (function Available -> Adopted) }]"
          | _ -> None)
        declaration.ptype_attributes
    with
    | Some fields -> fields
    | None ->
        Location.raise_errorf ~loc
          "[@@@@deriving workflow] needs [@@@@transitions { adopt = (function \
           Available -> Adopted) }]"
  in
  let state_of (expression : expression) =
    match expression.pexp_desc with
    | Pexp_construct ({ txt = Lident state; _ }, None)
      when List.mem state states ->
        state
    | _ ->
        Location.raise_errorf ~loc:expression.pexp_loc
          "a transition ends in one of the states (%s)"
          (String.concat ", " states)
  in
  let rec sources (pattern : pattern) =
    match pattern.ppat_desc with
    | Ppat_construct ({ txt = Lident state; _ }, None)
      when List.mem state states ->
        [ state ]
    | Ppat_or (left, right) -> sources left @ sources right
    | Ppat_any -> states
    | _ ->
        Location.raise_errorf ~loc:pattern.ppat_loc
          "a transition starts from states (%s), joined with |"
          (String.concat ", " states)
  in
  let parsed =
    List.map
      (fun (({ txt; loc } : longident loc), (cases : expression)) ->
        let name =
          match txt with
          | Lident name -> name
          | _ -> Location.raise_errorf ~loc "name the transition: adopt = …"
        in
        match cases.pexp_desc with
        | Pexp_function ([], None, Pfunction_cases (cases, _, _)) ->
            ( name,
              String.capitalize_ascii name,
              List.map
                (fun (case : case) ->
                  Option.iter
                    (fun (guard : expression) ->
                      Location.raise_errorf ~loc:guard.pexp_loc
                        "a transition is decided by states alone; move the \
                         condition into the service")
                    case.pc_guard;
                  (case.pc_lhs, sources case.pc_lhs, state_of case.pc_rhs))
                cases )
        | _ ->
            Location.raise_errorf ~loc:cases.pexp_loc
              "%s is a function from states to a state: (function Available -> \
               Adopted)"
              name)
      transitions
  in
  let type_name = declaration.ptype_name.txt in
  let state_type = ptyp_constr ~loc { txt = Lident type_name; loc } [] in
  let transition_type =
    ptyp_constr ~loc { txt = Lident (named "transition"); loc } []
  in
  let construct name = pexp_construct ~loc { txt = Lident name; loc } None in
  let all_transitions =
    elist ~loc
      (List.map (fun (_, constructor, _) -> construct constructor) parsed)
  in
  [
    pstr_type ~loc Recursive
      [
        type_declaration ~loc
          ~name:{ txt = named "transition"; loc }
          ~params:[] ~cstrs:[] ~private_:Public ~manifest:None
          ~kind:
            (Ptype_variant
               (List.map
                  (fun (_, constructor, _) ->
                    constructor_declaration ~loc
                      ~name:{ txt = constructor; loc } ~args:(Pcstr_tuple [])
                      ~res:None)
                  parsed));
      ];
    [%stri
      let [%p pvar ~loc (named "transitions")] : [%t transition_type] list =
        [%e all_transitions]];
    [%stri
      let [%p pvar ~loc (named "transition_name")] :
          [%t transition_type] -> string =
        [%e
          pexp_function_cases ~loc
            (List.map
               (fun (name, constructor, _) ->
                 case
                   ~lhs:
                     (ppat_construct ~loc
                        { txt = Lident constructor; loc }
                        None)
                   ~guard:None ~rhs:(estring ~loc name))
               parsed)]];
    [%stri
      let [%p pvar ~loc (named "next")] :
          [%t transition_type] -> [%t state_type] -> [%t state_type] option =
        [%e
          pexp_function_cases ~loc
            (List.map
               (fun (_, constructor, cases) ->
                 case
                   ~lhs:
                     (ppat_construct ~loc
                        { txt = Lident constructor; loc }
                        None)
                   ~guard:None
                   ~rhs:
                     {
                       (pexp_function_cases ~loc
                          (List.map
                             (fun (pattern, _, target) ->
                               case ~lhs:pattern ~guard:None
                                 ~rhs:[%expr Some [%e construct target]])
                             cases
                          @ [
                              case ~lhs:[%pat? _] ~guard:None ~rhs:[%expr None];
                            ]))
                       with
                       pexp_attributes =
                         [
                           attribute ~loc
                             ~name:{ txt = "ocaml.warning"; loc }
                             ~payload:
                               (PStr [ pstr_eval ~loc (estring ~loc "-11") [] ]);
                         ];
                     })
               parsed)]];
    [%stri
      let [%p pvar ~loc (named "apply")] =
       fun transition state ->
        Option.to_result
          ~none:(`Not_allowed (transition, state))
          ([%e evar ~loc (named "next")] transition state)];
    [%stri
      let [%p pvar ~loc (named "allowed")] =
       fun state ->
        List.filter_map
          (fun transition ->
            Option.map
              (fun _ -> transition)
              ([%e evar ~loc (named "next")] transition state))
          [%e evar ~loc (named "transitions")]];
    [%stri
      let [%p pvar ~loc (named "sources")] =
       fun transition ->
        List.filter_map
          (fun state ->
            Option.map
              (fun _ -> state)
              ([%e evar ~loc (named "next")] transition state))
          [%e elist ~loc (List.map construct states)]];
    [%stri
      let [%p pvar ~loc (named "workflow_mermaid")] =
        [%e
          estring ~loc
            (String.concat "\n"
               ("stateDiagram-v2"
                :: List.concat_map
                     (fun (name, _, cases) ->
                       List.concat_map
                         (fun (_, sources, target) ->
                           List.map
                             (fun source ->
                               Printf.sprintf "  %s --> %s: %s" source target
                                 name)
                             sources)
                         cases)
                     parsed
               @ [ "" ]))]];
  ]

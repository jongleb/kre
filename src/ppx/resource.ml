open Ppxlib
open Ast_builder.Default

(** A route [[%%resource]] generates. *)
type action =
  | Index of longident option  (** A page, filtered by [F.t] when given. *)
  | Show
  | Create of longident  (** Created from the body [D.t]. *)
  | Remove

let structure items =
  let expand ~loc payload =
    let usage () =
      Location.raise_errorf ~loc
        "[%%%%resource] takes { service = (module Cats : Cats_service.S); \
         entity = Cat; actions = [ Index Cat_filter; Show; Create Cat_draft; \
         Remove ] }"
    in
    let fields =
      match payload with
      | PStr
          [
            {
              pstr_desc =
                Pstr_eval ({ pexp_desc = Pexp_record (fields, None); _ }, _);
              _;
            };
          ] ->
          List.map
            (fun ((field : longident loc), value) ->
              (Longident.name field.txt, value))
            fields
      | _ -> usage ()
    in
    let field name =
      match List.assoc_opt name fields with
      | Some value -> value
      | None ->
          Location.raise_errorf ~loc "[%%%%resource] needs the field %s" name
    in
    let dependency, package =
      match (field "service").pexp_desc with
      | Pexp_constraint
          ( {
              pexp_desc =
                Pexp_pack { pmod_desc = Pmod_ident { txt = Lident name; _ }; _ };
              _;
            },
            ({ ptyp_desc = Ptyp_package _; _ } as package) ) ->
          (name, package)
      | _ ->
          Location.raise_errorf ~loc:(field "service").pexp_loc
            "service names the dependency the way a handler takes it: (module \
             Cats : Cats_service.S)"
    in
    let module_path (expression : expression) =
      match expression.pexp_desc with
      | Pexp_construct ({ txt; _ }, None) -> txt
      | _ ->
          Location.raise_errorf ~loc:expression.pexp_loc
            "expected a module name, e.g. Cat"
    in
    let entity = module_path (field "entity") in
    let actions =
      let rec elements (expression : expression) =
        match expression.pexp_desc with
        | Pexp_construct ({ txt = Lident "[]"; _ }, None) -> []
        | Pexp_construct
            ( { txt = Lident "::"; _ },
              Some { pexp_desc = Pexp_tuple [ head; tail ]; _ } ) ->
            (match head.pexp_desc with
            | Pexp_construct ({ txt = Lident "Index"; _ }, None) -> Index None
            | Pexp_construct ({ txt = Lident "Index"; _ }, Some filter) ->
                Index (Some (module_path filter))
            | Pexp_construct ({ txt = Lident "Show"; _ }, None) -> Show
            | Pexp_construct ({ txt = Lident "Create"; _ }, Some draft) ->
                Create (module_path draft)
            | Pexp_construct ({ txt = Lident "Remove"; _ }, None) -> Remove
            | _ ->
                Location.raise_errorf ~loc:head.pexp_loc
                  "an action is Index, Index Filter, Show, Create Draft or \
                   Remove")
            :: elements tail
        | _ ->
            Location.raise_errorf ~loc:expression.pexp_loc
              "actions is a list: [ Index Cat_filter; Show; Create Cat_draft; \
               Remove ]"
      in
      elements (field "actions")
    in
    let entity_type name arguments =
      ptyp_constr ~loc { txt = Ldot (entity, name); loc } arguments
    in
    let item = String.uncapitalize_ascii (Longident.last_exn entity) in
    let call name arguments =
      pexp_apply ~loc
        (pexp_ident ~loc { txt = Ldot (Lident dependency, name); loc })
        (List.map (fun argument -> (Nolabel, argument)) arguments)
    in
    let loaded =
      ppat_constraint ~loc (pvar ~loc item)
        {
          (entity_type "t" []) with
          ptyp_attributes =
            [
              attribute ~loc ~name:{ txt = "load"; loc }
                ~payload:
                  (PStr
                     [
                       pstr_eval ~loc
                         (pexp_ident ~loc
                            { txt = Ldot (Lident dependency, "find"); loc })
                         [];
                     ]);
            ];
        }
    in
    let searched type_ =
      {
        type_ with
        ptyp_attributes =
          [ attribute ~loc ~name:{ txt = "search"; loc } ~payload:(PStr []) ];
      }
    in
    let handler name parameters returns body attributes =
      pstr_value ~loc Nonrecursive
        [
          {
            (value_binding ~loc ~pat:(pvar ~loc name)
               ~expr:
                 (pexp_function ~loc
                    (pparam_val ~loc Nolabel None
                       (ppat_constraint ~loc
                          (ppat_unpack ~loc { txt = Some dependency; loc })
                          package)
                    :: parameters)
                    (Some (Pconstraint [%type: [%t returns] Lwt.t]))
                    (Pfunction_body body)))
            with
            pvb_attributes =
              List.map
                (fun (attribute_name, payload) ->
                  attribute ~loc
                    ~name:{ txt = attribute_name; loc }
                    ~payload:
                      (PStr
                         (List.map
                            (fun value -> pstr_eval ~loc value [])
                            payload)))
                attributes;
          };
        ]
    in
    let labelled label pattern =
      pparam_val ~loc (Labelled label) None pattern
    in
    let unit = pparam_val ~loc Nolabel None [%pat? ()] in
    List.map
      (function
        | Index filter ->
            handler "index"
              (Option.fold ~none:[]
                 ~some:(fun filter ->
                   [
                     labelled "filter"
                       (ppat_constraint ~loc (pvar ~loc "filter")
                          (searched
                             (ptyp_constr ~loc
                                { txt = Ldot (filter, "t"); loc }
                                [])));
                   ])
                 filter
              @ [
                  labelled "page"
                    (ppat_constraint ~loc (pvar ~loc "page")
                       (searched [%type: Kre_shared.Page.Request.t]));
                  unit;
                ])
              [%type: [%t entity_type "t" []] Kre_shared.Page.t]
              (call "page"
                 (Option.fold ~none:[]
                    ~some:(fun _ -> [ [%expr filter] ])
                    filter
                 @ [ [%expr page] ]))
              [ ("get", []) ]
        | Show ->
            handler "show"
              [ labelled item loaded ]
              (entity_type "t" [])
              [%expr Lwt.return [%e evar ~loc item]]
              [ ("get", [ estring ~loc (":" ^ item) ]) ]
        | Create draft ->
            handler "create"
              [
                labelled "body"
                  (ppat_constraint ~loc (pvar ~loc "body")
                     (ptyp_constr ~loc { txt = Ldot (draft, "t"); loc } []));
              ]
              (entity_type "t" [])
              (call "create" [ [%expr body] ])
              [ ("post", []); ("status", [ eint ~loc 201 ]) ]
        | Remove ->
            handler "remove"
              [ labelled item loaded ]
              [%type: unit]
              (call "remove" [ evar ~loc item ])
              [ ("delete", [ estring ~loc (":" ^ item) ]) ])
      actions
  in
  List.concat_map
    (fun (item : structure_item) ->
      match item.pstr_desc with
      | Pstr_extension (({ txt = "resource"; loc }, payload), _) ->
          expand ~loc payload
      | _ -> [ item ])
    items

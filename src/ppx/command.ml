open Ppxlib
open Ast_builder.Default

(** One parameter of a command function. *)
type parameter =
  | Dependency of string * pattern
      (** [(module Cats : Cats_service.S)]: the name and the whole pattern. *)
  | Required of string * expression  (** [~(count : int)], with its scalar. *)
  | Defaulted of string * expression * expression
      (** [?(count : int = 3)], with its scalar and default. *)
  | Unit

let structure items =
  List.concat_map
    (fun (item : structure_item) ->
      match item.pstr_desc with
      | Pstr_value (Nonrecursive, [ binding ]) -> (
          match
            ( binding.pvb_pat.ppat_desc,
              List.find_opt
                (fun (attribute : attribute) ->
                  String.equal attribute.attr_name.txt "command")
                binding.pvb_attributes )
          with
          | _, None -> [ item ]
          | Ppat_var { txt = name; _ }, Some attribute ->
              let loc = attribute.attr_loc in
              let doc =
                match attribute.attr_payload with
                | PStr
                    [
                      {
                        pstr_desc =
                          Pstr_eval
                            ( {
                                pexp_desc =
                                  Pexp_constant (Pconst_string (doc, _, _));
                                _;
                              },
                              _ );
                        _;
                      };
                    ] ->
                    doc
                | _ ->
                    Location.raise_errorf ~loc
                      "[@@@@command] takes what the command does: [@@@@command \
                       \"Seed the database\"]"
              in
              let scalar (type_ : core_type) =
                match type_.ptyp_desc with
                | Ptyp_constr ({ txt = Lident "int"; _ }, []) ->
                    [%expr (module Forge_shared.Scalar.Int)]
                | Ptyp_constr ({ txt = Lident "int64"; _ }, []) ->
                    [%expr (module Forge_shared.Scalar.Int64)]
                | Ptyp_constr ({ txt = Lident "float"; _ }, []) ->
                    [%expr (module Forge_shared.Scalar.Float)]
                | Ptyp_constr ({ txt = Lident "bool"; _ }, []) ->
                    [%expr (module Forge_shared.Scalar.Bool)]
                | Ptyp_constr ({ txt = Lident "string"; _ }, []) ->
                    [%expr (module Forge_shared.Scalar.String)]
                | Ptyp_constr ({ txt = Ldot (path, "t"); loc }, []) ->
                    pexp_pack ~loc (pmod_ident ~loc { txt = path; loc })
                | _ ->
                    Location.raise_errorf ~loc:type_.ptyp_loc
                      "a command option is int, int64, float, bool, string or \
                       M.t with M a Forge_shared.Scalar.S"
              in
              let parameters =
                match binding.pvb_expr.pexp_desc with
                | Pexp_function (params, _, _) ->
                    List.map
                      (fun (param : function_param) ->
                        match param.pparam_desc with
                        | Pparam_val
                            ( Nolabel,
                              None,
                              ({
                                 ppat_desc =
                                   Ppat_constraint
                                     ( {
                                         ppat_desc =
                                           Ppat_unpack { txt = Some module_; _ };
                                         _;
                                       },
                                       { ptyp_desc = Ptyp_package _; _ } );
                                 _;
                               } as pattern) ) ->
                            Dependency (module_, pattern)
                        | Pparam_val
                            ( Nolabel,
                              None,
                              {
                                ppat_desc =
                                  Ppat_construct ({ txt = Lident "()"; _ }, None);
                                _;
                              } ) ->
                            Unit
                        | Pparam_val
                            ( Labelled label,
                              None,
                              { ppat_desc = Ppat_constraint (_, type_); _ } ) ->
                            Required (label, scalar type_)
                        | Pparam_val
                            ( Optional label,
                              Some default,
                              { ppat_desc = Ppat_constraint (_, type_); _ } ) ->
                            Defaulted (label, scalar type_, default)
                        | _ ->
                            Location.raise_errorf ~loc:param.pparam_loc
                              "a command takes (module M : S) dependencies, \
                               ~(name : type) and ?(name : type = default) \
                               options, and ()")
                      params
                | _ ->
                    Location.raise_errorf ~loc
                      "[@@@@command] goes on a function: let %s (module Db : \
                       Forge.Db.S) ~(count : int) () = …"
                      name
              in
              let options =
                List.filter_map
                  (function
                    | Required (label, scalar) ->
                        Some
                          ( label,
                            [%expr
                              Forge.Command.required [%e scalar]
                                [%e estring ~loc label] __forge_args] )
                    | Defaulted (label, scalar, default) ->
                        Some
                          ( label,
                            [%expr
                              Forge.Command.optional [%e scalar]
                                [%e estring ~loc label] ~default:[%e default]
                                __forge_args] )
                    | Dependency _ | Unit -> None)
                  parameters
              in
              let call =
                [%expr
                  fun () ->
                    [%e
                      pexp_apply ~loc (evar ~loc name)
                        (List.map
                           (function
                             | Dependency (module_, _) ->
                                 ( Nolabel,
                                   pexp_pack ~loc
                                     (pmod_ident ~loc
                                        { txt = Lident module_; loc }) )
                             | Required (label, _) ->
                                 (Labelled label, evar ~loc label)
                             | Defaulted (label, _, _) ->
                                 (Labelled label, evar ~loc label)
                             | Unit -> (Nolabel, [%expr ()]))
                           parameters)]]
              in
              let build =
                match options with
                | [] -> [%expr Ok [%e call]]
                | (first, parse) :: rest ->
                    let binding (label, parse) op =
                      binding_op ~loc ~op:{ txt = op; loc }
                        ~pat:(pvar ~loc label) ~exp:parse
                    in
                    [%expr
                      let open Forge_shared.Validation.Syntax in
                      [%e
                        pexp_letop ~loc
                          (letop
                             ~let_:(binding (first, parse) "let+")
                             ~ands:
                               (List.map
                                  (fun option -> binding option "and+")
                                  rest)
                             ~body:call)]]
              in
              let command =
                [%expr
                  Forge.Command.make ~name:[%e estring ~loc name]
                    ~doc:[%e estring ~loc doc]
                    ~options:
                      [%e
                        elist ~loc
                          (List.map
                             (fun (label, _) -> estring ~loc label)
                             options)]
                    (fun __forge_args -> [%e build])]
              in
              [
                {
                  item with
                  pstr_desc =
                    Pstr_value
                      ( Nonrecursive,
                        [
                          {
                            binding with
                            pvb_attributes =
                              List.filter
                                (fun (attribute : attribute) ->
                                  not
                                    (String.equal attribute.attr_name.txt
                                       "command"))
                                binding.pvb_attributes;
                          };
                        ] );
                };
                [%stri
                  let [%p pvar ~loc ("__forge_command_" ^ name)] =
                    [%e
                      match
                        List.filter_map
                          (function
                            | Dependency (_, pattern) -> Some pattern
                            | Required _ | Defaulted _ | Unit -> None)
                          parameters
                      with
                      | [] -> [%expr fun () -> [%e command]]
                      | patterns ->
                          List.fold_right
                            (fun pattern body ->
                              pexp_fun ~loc Nolabel None pattern body)
                            patterns command]];
              ]
          | _, Some attribute ->
              Location.raise_errorf ~loc:attribute.attr_loc
                "[@@@@command] goes on a named function")
      | _ -> [ item ])
    items

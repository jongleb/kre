open Ppxlib
open Ast_builder.Default

(** What a gateway handler receives, in parameter order. *)
type input =
  | Dependency of { name : string; pattern : pattern }
  | Socket
  | Body of module_expr
  | Unit

type handler = {
  name : string;
  event : string;
  inputs : (arg_label * input) list;
  body : module_expr option;
  reply : module_expr option;  (** [None]: [unit Lwt.t], nothing sent back. *)
  outcome : [ `Plain | `Fallible ];
}

let transform structure =
  match structure with
  | {
      pstr_desc =
        Pstr_attribute ({ attr_name = { txt = "gateway"; _ }; _ } as gateway);
      _;
    }
    :: rest ->
      let loc = gateway.attr_loc in
      let path =
        match gateway.attr_payload with
        | PStr
            [
              {
                pstr_desc =
                  Pstr_eval
                    ( {
                        pexp_desc = Pexp_constant (Pconst_string (path, _, _));
                        _;
                      },
                      _ );
                _;
              };
            ] ->
            path
        | _ ->
            Location.raise_errorf ~loc
              "[@@@@@@gateway] takes its path: [@@@@@@gateway \"chat\"]"
      in
      let json (type_ : core_type) =
        let rec module_of (type_ : core_type) =
          match type_.ptyp_desc with
          | Ptyp_constr ({ txt = Lident "list"; _ }, [ element ]) ->
              pmod_apply ~loc
                (pmod_ident ~loc
                   { txt = Longident.parse "Forge_shared.Json.List"; loc })
                (module_of element)
          | Ptyp_constr
              ( {
                  txt =
                    Lident
                      (("int" | "int64" | "float" | "bool" | "string") as scalar);
                  _;
                },
                [] ) ->
              pmod_ident ~loc
                {
                  txt =
                    Longident.parse
                      ("Forge_shared.Scalar." ^ String.capitalize_ascii scalar);
                  loc;
                }
          | Ptyp_constr ({ txt = Ldot (path, "t"); loc }, []) ->
              pmod_ident ~loc { txt = path; loc }
          | _ ->
              Location.raise_errorf ~loc:type_.ptyp_loc
                "unsupported message type %a; use T.t with T : \
                 Forge_shared.Json.S, a scalar or a list"
                Pprintast.core_type type_
        in
        module_of type_
      in
      let handler (binding : value_binding) (event : string) =
        let name =
          match binding.pvb_pat.ppat_desc with
          | Ppat_var { txt; _ } -> txt
          | _ ->
              Location.raise_errorf ~loc:binding.pvb_pat.ppat_loc
                "[@@@@subscribe] needs a plain name"
        in
        match binding.pvb_expr.pexp_desc with
        | Pexp_function (params, Some (Pconstraint returns), _) ->
            let inputs =
              List.map
                (fun (param : function_param) ->
                  let loc = param.pparam_loc in
                  match param.pparam_desc with
                  | Pparam_val
                      ( Nolabel,
                        _,
                        ({
                           ppat_desc =
                             Ppat_constraint
                               ( {
                                   ppat_desc = Ppat_unpack { txt = Some name; _ };
                                   _;
                                 },
                                 { ptyp_desc = Ptyp_package _; _ } );
                           _;
                         } as pattern) ) ->
                      (Nolabel, Dependency { name; pattern })
                  | Pparam_val
                      ( Nolabel,
                        _,
                        {
                          ppat_desc =
                            Ppat_constraint
                              ( _,
                                {
                                  ptyp_desc =
                                    Ptyp_constr
                                      ({ txt = Ldot (_, "socket"); _ }, []);
                                  _;
                                } );
                          _;
                        } ) ->
                      (Nolabel, Socket)
                  | Pparam_val
                      ( Nolabel,
                        _,
                        {
                          ppat_desc =
                            Ppat_construct ({ txt = Lident "()"; _ }, None);
                          _;
                        } ) ->
                      (Nolabel, Unit)
                  | Pparam_val
                      ( Labelled "body",
                        _,
                        { ppat_desc = Ppat_constraint (_, type_); _ } ) ->
                      (Labelled "body", Body (json type_))
                  | _ ->
                      Location.raise_errorf ~loc
                        "a gateway handler takes (module M : S) dependencies, \
                         (socket : Forge.Gateway.socket), ~(body : T.t) and ()")
                params
            in
            let outcome, payload =
              match returns.ptyp_desc with
              | Ptyp_constr ({ txt = Ldot (Lident "Lwt", "t"); _ }, [ inner ])
                -> (
                  match inner.ptyp_desc with
                  | Ptyp_constr ({ txt = Lident "result"; _ }, [ ok; _ ]) ->
                      (`Fallible, ok)
                  | _ -> (`Plain, inner))
              | _ ->
                  Location.raise_errorf ~loc:returns.ptyp_loc
                    "gateway handler %s must return a promise: unit Lwt.t, T.t \
                     Lwt.t or (T.t, Forge.Error.t) result Lwt.t"
                    name
            in
            {
              name;
              event;
              inputs;
              body =
                List.find_map
                  (function _, Body module_ -> Some module_ | _ -> None)
                  inputs;
              reply =
                (match payload.ptyp_desc with
                | Ptyp_constr ({ txt = Lident "unit"; _ }, []) -> None
                | _ -> Some (json payload));
              outcome;
            }
        | Pexp_function (_, None, _) ->
            Location.raise_errorf ~loc:binding.pvb_expr.pexp_loc
              "gateway handler %s: add a return type annotation" name
        | _ ->
            Location.raise_errorf ~loc:binding.pvb_expr.pexp_loc
              "gateway handler %s must be a function" name
      in
      let subscribed (binding : value_binding) =
        List.find_map
          (fun (attribute : attribute) ->
            match (attribute.attr_name.txt, attribute.attr_payload) with
            | ( "subscribe",
                PStr
                  [
                    {
                      pstr_desc =
                        Pstr_eval
                          ( {
                              pexp_desc =
                                Pexp_constant (Pconst_string (event, _, _));
                              _;
                            },
                            _ );
                      _;
                    };
                  ] ) ->
                Some event
            | "subscribe", _ ->
                Location.raise_errorf ~loc:attribute.attr_loc
                  "[@@@@subscribe] takes the event name: [@@@@subscribe \
                   \"message\"]"
            | _ -> None)
          binding.pvb_attributes
      in
      let handlers =
        List.concat_map
          (fun (item : structure_item) ->
            match item.pstr_desc with
            | Pstr_value (_, bindings) ->
                List.filter_map
                  (fun binding ->
                    Option.map (handler binding) (subscribed binding))
                  bindings
            | _ -> [])
          rest
      in
      let dependencies =
        List.fold_left
          (fun known (_, input) ->
            match input with
            | Dependency { name; pattern } when not (List.mem_assoc name known)
              ->
                known @ [ (name, pattern) ]
            | Dependency _ | Socket | Body _ | Unit -> known)
          []
          (List.concat_map (fun handler -> handler.inputs) handlers)
      in
      let wrap handler =
        let call =
          pexp_apply ~loc (evar ~loc handler.name)
            (List.map
               (fun (label, input) ->
                 ( label,
                   match input with
                   | Dependency { name; _ } ->
                       pexp_pack ~loc
                         (pmod_ident ~loc { txt = Lident name; loc })
                   | Socket -> [%expr __forge_socket]
                   | Body _ -> [%expr __forge_body]
                   | Unit -> [%expr ()] ))
               handler.inputs)
        in
        let result =
          match handler.outcome with
          | `Plain -> [%expr Lwt.map Result.ok [%e call]]
          | `Fallible -> call
        in
        let body_module =
          Option.value handler.body
            ~default:
              (pmod_ident ~loc
                 { txt = Longident.parse "Forge_shared.Json.Ignored"; loc })
        in
        match handler.reply with
        | Some reply ->
            [%expr
              Forge.Gateway.on [%e estring ~loc handler.event]
                [%e pexp_pack ~loc body_module] [%e pexp_pack ~loc reply]
                (fun __forge_socket __forge_body -> [%e result])]
        | None ->
            [%expr
              Forge.Gateway.notify [%e estring ~loc handler.event]
                [%e pexp_pack ~loc body_module]
                (fun __forge_socket __forge_body -> [%e result])]
      in
      let abstract body =
        match dependencies with
        | [] -> [%expr fun () -> [%e body]]
        | _ ->
            List.fold_right
              (fun (_, pattern) body -> pexp_fun ~loc Nolabel None pattern body)
              dependencies body
      in
      let applied =
        pexp_apply ~loc [%expr gateway]
          (match dependencies with
          | [] -> [ (Nolabel, [%expr ()]) ]
          | _ ->
              List.map
                (fun (name, _) ->
                  ( Nolabel,
                    pexp_pack ~loc (pmod_ident ~loc { txt = Lident name; loc })
                  ))
                dependencies)
      in
      List.filter
        (fun (item : structure_item) ->
          match item.pstr_desc with Pstr_attribute _ -> false | _ -> true)
        rest
      @ [
          [%stri
            let gateway =
              [%e
                abstract
                  [%expr
                    Forge.Gateway.make [%e elist ~loc (List.map wrap handlers)]]]];
          [%stri
            let register =
              [%e
                abstract
                  [%expr
                    Forge.Gateway.controller ~path:[%e estring ~loc path]
                      [%e applied]]]];
        ]
  | _ -> structure

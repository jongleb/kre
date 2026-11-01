open Ppxlib
open Ast_builder.Default

(** Where one argument of a declared call goes. *)
type argument =
  | Segment of string * module_expr  (** [~login] for [:login] in the path. *)
  | Query of string * module_expr * [ `Required | `Optional ]
  | Body of module_expr
  | Unit

let scalar ~loc (type_ : core_type) =
  let ident path = pmod_ident ~loc { txt = Longident.parse path; loc } in
  match type_.ptyp_desc with
  | Ptyp_constr ({ txt = Lident "int"; _ }, []) ->
      ident "Forge_shared.Scalar.Int"
  | Ptyp_constr ({ txt = Lident "int64"; _ }, []) ->
      ident "Forge_shared.Scalar.Int64"
  | Ptyp_constr ({ txt = Lident "float"; _ }, []) ->
      ident "Forge_shared.Scalar.Float"
  | Ptyp_constr ({ txt = Lident "bool"; _ }, []) ->
      ident "Forge_shared.Scalar.Bool"
  | Ptyp_constr ({ txt = Lident "string"; _ }, []) ->
      ident "Forge_shared.Scalar.String"
  | Ptyp_constr ({ txt = Ldot (path, "t"); loc }, []) ->
      pmod_ident ~loc { txt = path; loc }
  | _ ->
      Location.raise_errorf ~loc:type_.ptyp_loc
        "a path or query value is int, int64, float, bool, string or M.t with \
         M : Forge_shared.Scalar.S"

let rec json ~loc (type_ : core_type) =
  match type_.ptyp_desc with
  | Ptyp_constr ({ txt = Lident "list"; _ }, [ element ]) ->
      pmod_apply ~loc
        (pmod_ident ~loc
           { txt = Longident.parse "Forge_shared.Json.List"; loc })
        (json ~loc element)
  | Ptyp_constr ({ txt = Ldot (path, "t"); loc }, [ element ]) ->
      pmod_apply ~loc
        (pmod_ident ~loc { txt = Ldot (path, "Make"); loc })
        (json ~loc element)
  | _ -> scalar ~loc type_

let call ~loc (value : value_description) =
  let verb, path =
    match
      List.filter_map
        (fun (attribute : attribute) ->
          match
            ( List.assoc_opt attribute.attr_name.txt
                [
                  ("get", `GET);
                  ("post", `POST);
                  ("put", `PUT);
                  ("patch", `PATCH);
                  ("delete", `DELETE);
                ],
              attribute.attr_payload )
          with
          | ( Some verb,
              PStr
                [
                  {
                    pstr_desc =
                      Pstr_eval
                        ( {
                            pexp_desc =
                              Pexp_constant (Pconst_string (path, _, _));
                            _;
                          },
                          _ );
                    _;
                  };
                ] ) ->
              Some (verb, path)
          | Some _, _ ->
              Location.raise_errorf ~loc:attribute.attr_loc
                "[@@@@%s] takes the path: [@@@@%s \"/users/:login\"]"
                attribute.attr_name.txt attribute.attr_name.txt
          | None, _ -> None)
        value.pval_attributes
    with
    | [ found ] -> found
    | _ ->
        Location.raise_errorf ~loc:value.pval_loc
          "%s needs one verb with a path: [@@@@get \"/users/:login\"]"
          value.pval_name.txt
  in
  let segments =
    List.filter (fun segment -> segment <> "") (String.split_on_char '/' path)
  in
  let parameter segment =
    match String.split_on_char ':' segment with
    | [ ""; name ] when name <> "" -> Some name
    | _ -> None
  in
  let names = List.filter_map parameter segments in
  let rec arguments (type_ : core_type) =
    match type_.ptyp_desc with
    | Ptyp_arrow (label, argument, rest) ->
        let parameter, (more, result) =
          ( (match (label, argument.ptyp_desc) with
            | Labelled name, _ when List.mem name names ->
                (label, Segment (name, scalar ~loc argument))
            | Labelled "body", _ -> (label, Body (json ~loc argument))
            | Labelled name, _ ->
                (label, Query (name, scalar ~loc argument, `Required))
            | Optional name, _ ->
                (label, Query (name, scalar ~loc argument, `Optional))
            | Nolabel, Ptyp_constr ({ txt = Lident "unit"; _ }, []) ->
                (label, Unit)
            | Nolabel, _ ->
                Location.raise_errorf ~loc:argument.ptyp_loc
                  "label the argument: ~login:string, ?per_page:int, ~body:T.t"),
            arguments rest )
        in
        (parameter :: more, result)
    | _ -> ([], type_)
  in
  let parameters, result = arguments value.pval_type in
  Option.iter
    (fun name ->
      Location.raise_errorf ~loc:value.pval_loc
        "the path has :%s; add ~%s to %s" name name value.pval_name.txt)
    (List.find_opt
       (fun name ->
         not
           (List.exists
              (function
                | _, Segment (segment, _) -> String.equal segment name
                | _, (Query _ | Body _ | Unit) -> false)
              parameters))
       names);
  let returns =
    match result.ptyp_desc with
    | Ptyp_constr ({ txt = Lident "unit"; _ }, []) ->
        [%expr Forge_client.Wire.Unit]
    | Ptyp_constr ({ txt = Lident "string"; _ }, []) ->
        [%expr Forge_client.Wire.Text]
    | _ -> [%expr Forge_client.Wire.Json [%e pexp_pack ~loc (json ~loc result)]]
  in
  let request =
    pexp_apply ~loc [%expr Forge_client.Http.request]
      ([
         (Labelled "base", [%expr Config.url]);
         ( Nolabel,
           pexp_variant ~loc
             (match verb with
             | `GET -> "GET"
             | `POST -> "POST"
             | `PUT -> "PUT"
             | `PATCH -> "PATCH"
             | `DELETE -> "DELETE")
             None );
         ( Labelled "path",
           elist ~loc
             (List.map
                (fun segment ->
                  Option.value ~default:(estring ~loc segment)
                    (Option.bind (parameter segment) (fun name ->
                         List.find_map
                           (function
                             | _, Segment (found, module_)
                               when String.equal found name ->
                                 Some
                                   [%expr
                                     Forge_client.Wire.segment
                                       [%e pexp_pack ~loc module_]
                                       [%e evar ~loc name]]
                             | _ -> None)
                           parameters)))
                segments) );
         ( Labelled "query",
           elist ~loc
             (List.filter_map
                (function
                  | _, Query (name, module_, presence) ->
                      Some
                        [%expr
                          Forge_client.Wire.query [%e pexp_pack ~loc module_]
                            [%e
                              match presence with
                              | `Required ->
                                  [%expr Forge_shared.Presence.Required]
                              | `Optional ->
                                  [%expr Forge_shared.Presence.Optional]]
                            [%e estring ~loc name] [%e evar ~loc name]]
                  | _, (Segment _ | Body _ | Unit) -> None)
                parameters) );
         (Labelled "headers", [%expr [ Config.headers ]]);
       ]
      @ List.filter_map
          (function
            | _, Body module_ ->
                Some
                  ( Labelled "body",
                    [%expr
                      Forge_client.Wire.body [%e pexp_pack ~loc module_] body]
                  )
            | _, (Segment _ | Query _ | Unit) -> None)
          parameters
      @ [ (Nolabel, returns) ])
  in
  let promise =
    match !Table.target with
    | Table.Native -> fun type_ -> [%type: [%t type_] Lwt.t]
    | Table.Melange -> fun type_ -> [%type: [%t type_] Js.Promise.t]
  in
  let rec declared (type_ : core_type) =
    match type_.ptyp_desc with
    | Ptyp_arrow (label, argument, rest) ->
        ptyp_arrow ~loc label argument (declared rest)
    | _ -> promise [%type: ([%t result], Forge_client.Error.t) result]
  in
  ( pstr_value ~loc Nonrecursive
      [
        value_binding ~loc
          ~pat:(pvar ~loc value.pval_name.txt)
          ~expr:
            (List.fold_right
               (fun (label, parameter) body ->
                 pexp_fun ~loc label None
                   (match parameter with
                   | Unit -> [%pat? ()]
                   | Segment (name, _) | Query (name, _, _) -> pvar ~loc name
                   | Body _ -> pvar ~loc "body")
                   body)
               parameters request);
      ],
    psig_value ~loc
      (value_description ~loc ~name:value.pval_name
         ~type_:(declared value.pval_type) ~prim:[]) )

let extension =
  Extension.V3.declare "http_client" Extension.Context.module_expr
    Ast_pattern.(psig __)
    (fun ~ctxt items ->
      let loc = Expansion_context.Extension.extension_point_loc ctxt in
      let calls =
        List.map
          (fun (item : signature_item) ->
            match item.psig_desc with
            | Psig_value value -> call ~loc value
            | _ ->
                Location.raise_errorf ~loc:item.psig_loc
                  "[%%http_client] lists calls: val user : login:string -> \
                   User.t [@@@@get \"/users/:login\"]")
          items
      in
      pmod_functor ~loc
        (Named
           ( { txt = Some "Config"; loc },
             pmty_signature ~loc
               [
                 psig_value ~loc
                   (value_description ~loc ~name:{ txt = "url"; loc }
                      ~type_:[%type: string] ~prim:[]);
                 psig_value ~loc
                   (value_description ~loc ~name:{ txt = "headers"; loc }
                      ~type_:[%type: (string * string) list] ~prim:[]);
               ] ))
        (pmod_constraint ~loc
           (pmod_structure ~loc (List.map fst calls))
           (pmty_signature ~loc (List.map snd calls))))

open Ppxlib
open Ast_builder.Default

(** Which compiler the deriver runs for; Melange gets no table code. *)
type target = Native | Melange

let target = ref Native

let structure ~ctxt (_, declarations) table_name =
  let loc = Expansion_context.Deriver.derived_item_loc ctxt in
  match !target with
  | Melange -> []
  | Native ->
      let type_name, labels =
        match declarations with
        | [ ({ ptype_kind = Ptype_record labels; _ } as declaration) ] ->
            (declaration.ptype_name.txt, labels)
        | _ ->
            Location.raise_errorf ~loc
              "[@@@@deriving table] works on one record type"
      in
      let table_name =
        match table_name with
        | Some name -> name
        | None ->
            Location.raise_errorf ~loc
              "[@@@@deriving table] needs the table name: [@@@@deriving table \
               ~name:\"cats\"]"
      in
      let value_name suffix =
        match type_name with "t" -> suffix | name -> name ^ "_" ^ suffix
      in
      let column (label : label_declaration) =
        let loc = label.pld_loc in
        let attribute name =
          List.find_opt
            (fun (attribute : attribute) ->
              String.equal attribute.attr_name.txt name)
            label.pld_attributes
        in
        let payload name =
          Option.map
            (fun (attribute : attribute) ->
              match attribute.attr_payload with
              | PStr [ { pstr_desc = Pstr_eval (expression, _); _ } ] ->
                  expression
              | _ ->
                  Location.raise_errorf ~loc:attribute.attr_loc
                    "[@@%s] expects an expression" name)
            (attribute name)
        in
        let role =
          match
            List.filter_map
              (fun name -> Option.map (fun _ -> name) (attribute name))
              [ "primary"; "auto"; "unique"; "index" ]
          with
          | [] -> None
          | [ "primary"; "auto" ] -> Some [%expr Forge.Table.Primary_auto]
          | [ "primary" ] -> Some [%expr Forge.Table.Primary]
          | [ "unique" ] -> Some [%expr Forge.Table.Unique]
          | [ "index" ] -> Some [%expr Forge.Table.Index]
          | [ "auto" ] ->
              Location.raise_errorf ~loc
                "[@@auto] needs [@@primary]: only an integer primary key \
                 increments"
          | roles ->
              Location.raise_errorf ~loc
                "field %s has several key roles (%s); keep one of [@@primary], \
                 [@@unique], [@@index]"
                label.pld_name.txt (String.concat ", " roles)
        in
        let nullability, base =
          match label.pld_type.ptyp_desc with
          | Ptyp_constr ({ txt = Lident "option"; _ }, [ element ]) ->
              (`Null, element)
          | _ -> (`Not_null, label.pld_type)
        in
        let size =
          Option.fold ~none:[%expr None]
            ~some:(fun size -> [%expr Some [%e size]])
            (payload "size")
        in
        let primitive name =
          match name with
          | "int" ->
              Some
                ( [%expr Forge.Table.Integer],
                  [%type: int64],
                  fun value -> [%expr Int64.to_int [%e value]] )
          | "int64" ->
              Some
                ([%expr Forge.Table.Integer], [%type: int64], fun value -> value)
          | "string" ->
              Some
                ( [%expr Forge.Table.Text [%e size]],
                  [%type: string],
                  fun value -> value )
          | "bool" ->
              Some
                ([%expr Forge.Table.Boolean], [%type: bool], fun value -> value)
          | "float" ->
              Some
                ([%expr Forge.Table.Double], [%type: float], fun value -> value)
          | _ -> None
        in
        let sql_type, row_type, convert =
          match base.ptyp_desc with
          | Ptyp_constr ({ txt = Lident name; _ }, []) -> (
              match primitive name with
              | Some found -> found
              | None ->
                  Location.raise_errorf ~loc:base.ptyp_loc
                    "unsupported column type %s; use int, int64, string, bool, \
                     float, T.t with [@@column …] or an option of those"
                    name)
          | Ptyp_constr ({ txt = Ldot (path, "t"); _ }, []) -> (
              let module_ = pmod_ident ~loc { txt = path; loc } in
              let unnamed () =
                Location.raise_errorf ~loc:base.ptyp_loc
                  "field %s has abstract type %a; name its column type: \
                   [@@column int], [@@column string], [@@column bool] or \
                   [@@column float]"
                  label.pld_name.txt Pprintast.core_type base
              in
              match payload "column" with
              | Some { pexp_desc = Pexp_ident { txt = Lident name; _ }; _ } -> (
                  match primitive name with
                  | Some (sql_type, row_type, to_base) ->
                      ( sql_type,
                        row_type,
                        fun value ->
                          [%expr
                            Forge.Table.decode [%e pexp_pack ~loc module_]
                              [%e
                                match name with
                                | "string" -> to_base value
                                | "int" | "int64" ->
                                    [%expr Int64.to_string [%e value]]
                                | "bool" -> [%expr string_of_bool [%e value]]
                                | _ ->
                                    [%expr
                                      Forge_shared.Scalar.Float.to_string
                                        [%e value]]]] )
                  | None -> unnamed ())
              | Some _ | None -> unnamed ())
          | _ ->
              Location.raise_errorf ~loc:base.ptyp_loc
                "unsupported column type %a" Pprintast.core_type base
        in
        let value = evar ~loc label.pld_name.txt in
        ( pexp_apply ~loc [%expr Forge.Table.column]
            (List.concat
               [
                 Option.fold ~none:[]
                   ~some:(fun role -> [ (Labelled "role", role) ])
                   role;
                 Option.fold ~none:[]
                   ~some:(fun default -> [ (Labelled "default", default) ])
                   (payload "sql.default");
                 Option.fold ~none:[]
                   ~some:(fun (references : expression) ->
                     match references.pexp_desc with
                     | Pexp_construct ({ txt; loc }, None) ->
                         [
                           ( Labelled "references",
                             pexp_ident ~loc { txt = Ldot (txt, "table"); loc }
                           );
                         ]
                     | _ ->
                         Location.raise_errorf ~loc:references.pexp_loc
                           "[@@references] takes a module with a table, e.g. \
                            [@@references User]")
                   (payload "references");
                 [
                   (Nolabel, estring ~loc label.pld_name.txt);
                   (Nolabel, sql_type);
                   ( Nolabel,
                     match nullability with
                     | `Null -> [%expr Forge.Table.Null]
                     | `Not_null -> [%expr Forge.Table.Not_null] );
                 ];
               ]),
          ( Labelled label.pld_name.txt,
            (match nullability with
            | `Null ->
                [%expr
                  Option.map
                    (fun value -> [%e convert [%expr value]])
                    [%e value]]
            | `Not_null -> convert value),
            match nullability with
            | `Null -> [%type: [%t row_type] option]
            | `Not_null -> row_type ) )
      in
      let columns = List.map column labels in
      [
        [%stri
          let [%p pvar ~loc (value_name "table")] : Forge.Table.t =
            Forge.Table.make ~name:[%e estring ~loc table_name]
              [%e elist ~loc (List.map fst columns)]];
        [%stri
          let [%p pvar ~loc (value_name "of_row")] =
            [%e
              List.fold_right
                (fun ((label : label_declaration), (_, (arg_label, _, row_type)))
                     body ->
                  pexp_fun ~loc arg_label None
                    (ppat_constraint ~loc
                       (pvar ~loc label.pld_name.txt)
                       row_type)
                    body)
                (List.combine labels columns)
                (pexp_constraint ~loc
                   (pexp_record ~loc
                      (List.map2
                         (fun (label : label_declaration) (_, (_, converted, _))
                            ->
                           ({ txt = Lident label.pld_name.txt; loc }, converted))
                         labels columns)
                      None)
                   (ptyp_constr ~loc { txt = Lident type_name; loc } []))]];
      ]

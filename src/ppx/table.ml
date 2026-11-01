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
      let records =
        List.map
          (fun (declaration : type_declaration) ->
            match declaration.ptype_kind with
            | Ptype_record labels -> (declaration.ptype_name.txt, labels)
            | _ ->
                Location.raise_errorf ~loc:declaration.ptype_loc
                  "[@@@@deriving table] works on record types; %s is not one"
                  declaration.ptype_name.txt)
          declarations
      in
      let embedded (label : label_declaration) =
        Option.map
          (fun (attribute : attribute) ->
            match label.pld_type.ptyp_desc with
            | Ptyp_constr ({ txt = Lident name; _ }, []) -> (
                match List.assoc_opt name records with
                | Some labels -> labels
                | None ->
                    Location.raise_errorf ~loc:attribute.attr_loc
                      "[@@embedded] stores a record of the same type group: \
                       type address = { … } and t = { home : address \
                       [@@embedded]; … }")
            | _ ->
                Location.raise_errorf ~loc:attribute.attr_loc
                  "[@@embedded] takes a record type of the same group, not %a"
                  Pprintast.core_type label.pld_type)
          (List.find_opt
             (fun (attribute : attribute) ->
               String.equal attribute.attr_name.txt "embedded")
             label.pld_attributes)
      in
      let type_name, fields =
        match
          List.filter
            (fun (name, _) ->
              not
                (List.exists
                   (fun (_, labels) ->
                     List.exists
                       (fun (label : label_declaration) ->
                         match (embedded label, label.pld_type.ptyp_desc) with
                         | Some _, Ptyp_constr ({ txt = Lident used; _ }, []) ->
                             String.equal used name
                         | _ -> false)
                       labels)
                   records))
            records
        with
        | [ (type_name, labels) ] ->
            let rec flatten path labels =
              List.concat_map
                (fun (label : label_declaration) ->
                  let path = path @ [ label.pld_name.txt ] in
                  Option.fold
                    ~none:
                      [
                        ( path,
                          {
                            label with
                            pld_name =
                              {
                                label.pld_name with
                                txt = String.concat "_" path;
                              };
                          } );
                      ]
                    ~some:(flatten path) (embedded label))
                labels
            in
            (type_name, flatten [] labels)
        | _ ->
            Location.raise_errorf ~loc
              "[@@@@deriving table] needs one record that the others are \
               [@@embedded] in"
      in
      let labels = List.map snd fields in
      let access (label : label_declaration) =
        List.fold_left
          (fun record name -> pexp_field ~loc record { txt = Lident name; loc })
          [%expr __kre_record]
          (List.assoc label.pld_name.txt
             (List.map
                (fun (path, (column : label_declaration)) ->
                  (column.pld_name.txt, path))
                fields))
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
      let is_time (type_ : core_type) =
        match type_.ptyp_desc with
        | Ptyp_constr
            ({ txt = Ldot (Ldot (Lident "Kre_shared", "Time"), "t"); _ }, []) ->
            Some ()
        | _ -> None
      in
      let managed (label : label_declaration) =
        match
          List.filter_map
            (fun (attribute : attribute) ->
              match attribute.attr_name.txt with
              | "created_at" -> Some (`Created_at, attribute)
              | "updated_at" -> Some (`Updated_at, attribute)
              | "version" -> Some (`Version, attribute)
              | _ -> None)
            label.pld_attributes
        with
        | [] -> None
        | [ (((`Created_at | `Updated_at) as kind), attribute) ] -> (
            match is_time label.pld_type with
            | Some () -> Some kind
            | None ->
                Location.raise_errorf ~loc:attribute.attr_loc
                  "[@@%s] fills a timestamp; give %s the type Kre_shared.Time.t"
                  attribute.attr_name.txt label.pld_name.txt)
        | [ (`Version, attribute) ] -> (
            match label.pld_type.ptyp_desc with
            | Ptyp_constr ({ txt = Lident "int"; _ }, []) -> Some `Version
            | _ ->
                Location.raise_errorf ~loc:attribute.attr_loc
                  "[@@version] counts updates; give %s the type int"
                  label.pld_name.txt)
        | _ :: (_, attribute) :: _ ->
            Location.raise_errorf ~loc:attribute.attr_loc
              "field %s takes one of [@@created_at], [@@updated_at], \
               [@@version]"
              label.pld_name.txt
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
          | [ "primary"; "auto" ] -> Some [%expr Kre.Table.Primary_auto]
          | [ "primary" ] -> Some [%expr Kre.Table.Primary]
          | [ "unique" ] -> Some [%expr Kre.Table.Unique]
          | [ "index" ] -> Some [%expr Kre.Table.Index]
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
        let ulid = attribute "ulid" in
        let size =
          Option.fold
            ~none:
              (Option.fold ~none:[%expr None]
                 ~some:(fun _ -> [%expr Some 26])
                 ulid)
            ~some:(fun size -> [%expr Some [%e size]])
            (payload "size")
        in
        let primitive name =
          match name with
          | "int" ->
              Some
                ( [%expr Kre.Table.Integer],
                  [%type: int64],
                  fun value -> [%expr Int64.to_int [%e value]] )
          | "int64" ->
              Some
                ([%expr Kre.Table.Integer], [%type: int64], fun value -> value)
          | "string" ->
              Some
                ( [%expr Kre.Table.Text [%e size]],
                  [%type: string],
                  fun value -> value )
          | "bool" ->
              Some ([%expr Kre.Table.Boolean], [%type: bool], fun value -> value)
          | "float" ->
              Some ([%expr Kre.Table.Double], [%type: float], fun value -> value)
          | _ -> None
        in
        let sql_type, row_type, convert =
          match (base.ptyp_desc, is_time base) with
          | _, Some () ->
              ( [%expr Kre.Table.Double],
                [%type: float],
                fun value -> [%expr Kre_shared.Time.of_seconds [%e value]] )
          | Ptyp_constr ({ txt = Lident name; _ }, []), None -> (
              match primitive name with
              | Some found -> found
              | None ->
                  Location.raise_errorf ~loc:base.ptyp_loc
                    "unsupported column type %s; use int, int64, string, bool, \
                     float, T.t with [@@column …] or an option of those"
                    name)
          | Ptyp_constr ({ txt = Ldot (path, "t"); _ }, []), None -> (
              let module_ = pmod_ident ~loc { txt = path; loc } in
              let unnamed () =
                Location.raise_errorf ~loc:base.ptyp_loc
                  "field %s has abstract type %a; name its column type: \
                   [@@column int], [@@column string], [@@column bool] or \
                   [@@column float]"
                  label.pld_name.txt Pprintast.core_type base
              in
              match
                Option.fold
                  ~none:(Option.map (fun _ -> [%expr string]) ulid)
                  ~some:Option.some (payload "column")
              with
              | Some { pexp_desc = Pexp_ident { txt = Lident name; _ }; _ } -> (
                  match primitive name with
                  | Some (sql_type, row_type, to_base) ->
                      ( sql_type,
                        row_type,
                        fun value ->
                          [%expr
                            Kre.Table.decode [%e pexp_pack ~loc module_]
                              [%e
                                match name with
                                | "string" -> to_base value
                                | "int" | "int64" ->
                                    [%expr Int64.to_string [%e value]]
                                | "bool" -> [%expr string_of_bool [%e value]]
                                | _ ->
                                    [%expr
                                      Kre_shared.Scalar.Float.to_string
                                        [%e value]]]] )
                  | None -> unnamed ())
              | Some _ | None -> unnamed ())
          | _, None ->
              Location.raise_errorf ~loc:base.ptyp_loc
                "unsupported column type %a" Pprintast.core_type base
        in
        let value = evar ~loc label.pld_name.txt in
        ( pexp_apply ~loc [%expr Kre.Table.column]
            (List.concat
               [
                 Option.fold ~none:[]
                   ~some:(fun role -> [ (Labelled "role", role) ])
                   role;
                 Option.fold ~none:[]
                   ~some:(fun (filter : expression) ->
                     match filter.pexp_desc with
                     | Pexp_construct
                         ( {
                             txt =
                               Lident (("Exact" | "Partial" | "Range") as kind);
                             loc;
                           },
                           None ) ->
                         [
                           ( Labelled "filter",
                             pexp_construct ~loc
                               {
                                 txt = Ldot (Ldot (Lident "Kre", "Table"), kind);
                                 loc;
                               }
                               None );
                         ]
                     | _ ->
                         Location.raise_errorf ~loc:filter.pexp_loc
                           "[@@filter] is Exact, Partial or Range")
                   (payload "filter");
                 Option.fold ~none:[]
                   ~some:(fun kind ->
                     [
                       ( Labelled "managed",
                         match kind with
                         | `Created_at -> [%expr Kre.Table.Created_at]
                         | `Updated_at -> [%expr Kre.Table.Updated_at]
                         | `Version -> [%expr Kre.Table.Version] );
                     ])
                   (managed label);
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
                     | `Null -> [%expr Kre.Table.Null]
                     | `Not_null -> [%expr Kre.Table.Not_null] );
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
      let encode (label : label_declaration) value =
        let loc = label.pld_loc in
        let nullable, base =
          match label.pld_type.ptyp_desc with
          | Ptyp_constr ({ txt = Lident "option"; _ }, [ element ]) ->
              (`Null, element)
          | _ -> (`Not_null, label.pld_type)
        in
        let one value =
          match (base.ptyp_desc, is_time base) with
          | _, Some () -> [%expr Kre_shared.Time.to_seconds [%e value]]
          | Ptyp_constr ({ txt = Lident "int"; _ }, []), None ->
              [%expr Int64.of_int [%e value]]
          | Ptyp_constr ({ txt = Ldot (path, "t"); _ }, []), None -> (
              let text =
                [%expr
                  [%e pexp_ident ~loc { txt = Ldot (path, "to_string"); loc }]
                    [%e value]]
              in
              match
                List.find_map
                  (fun (attribute : attribute) ->
                    match (attribute.attr_name.txt, attribute.attr_payload) with
                    | ( "column",
                        PStr
                          [
                            {
                              pstr_desc =
                                Pstr_eval
                                  ( {
                                      pexp_desc =
                                        Pexp_ident { txt = Lident kind; _ };
                                      _;
                                    },
                                    _ );
                              _;
                            };
                          ] ) ->
                        Some kind
                    | _ -> None)
                  label.pld_attributes
              with
              | Some ("int" | "int64") -> [%expr Int64.of_string [%e text]]
              | Some "bool" -> [%expr bool_of_string [%e text]]
              | Some "float" -> [%expr float_of_string [%e text]]
              | Some _ | None -> text)
          | _, None -> value
        in
        match nullable with
        | `Null ->
            [%expr Option.map (fun value -> [%e one [%expr value]]) [%e value]]
        | `Not_null -> one value
      in
      let has (label : label_declaration) name =
        List.exists
          (fun (attribute : attribute) ->
            String.equal attribute.attr_name.txt name)
          label.pld_attributes
      in
      let spread fields =
        [%expr
          fun (__kre_record :
                [%t ptyp_constr ~loc { txt = Lident type_name; loc } []])
              __kre_query ->
            let __kre_now = Kre.Table.now () in
            [%e
              pexp_apply ~loc [%expr __kre_query]
                (List.map
                   (fun ((label : label_declaration), filled) ->
                     ( Labelled label.pld_name.txt,
                       Option.value filled
                         ~default:(encode label (access label)) ))
                   fields)]]
      in
      let now = [%expr Kre_shared.Time.to_seconds __kre_now] in
      let slug (label : label_declaration) =
        Option.map
          (fun (attribute : attribute) ->
            match attribute.attr_payload with
            | PStr
                [
                  {
                    pstr_desc =
                      Pstr_eval
                        ( {
                            pexp_desc = Pexp_ident { txt = Lident source; _ };
                            _;
                          },
                          _ );
                    _;
                  };
                ] -> (
                match
                  List.find_opt
                    (fun (other : label_declaration) ->
                      String.equal other.pld_name.txt source)
                    labels
                with
                | Some other ->
                    [%expr
                      Kre_shared.Slug.of_string [%e encode other (access other)]]
                | None ->
                    Location.raise_errorf ~loc:attribute.attr_loc
                      "[@@slug_from %s]: the record has no field %s" source
                      source)
            | _ ->
                Location.raise_errorf ~loc:attribute.attr_loc
                  "[@@slug_from] names the field to build the slug from: \
                   [@@slug_from name]")
          (List.find_opt
             (fun (attribute : attribute) ->
               String.equal attribute.attr_name.txt "slug_from")
             label.pld_attributes)
      in
      [
        [%stri
          let [%p pvar ~loc (value_name "table")] : Kre.Table.t =
            [%e
              pexp_apply ~loc [%expr Kre.Table.make]
                (Option.fold ~none:[]
                   ~some:(fun (attribute : attribute) ->
                     match attribute.attr_payload with
                     | PStr [ { pstr_desc = Pstr_eval (scopes, _); _ } ] ->
                         [ (Labelled "scopes", scopes) ]
                     | _ ->
                         Location.raise_errorf ~loc:attribute.attr_loc
                           "[@@@@scopes] lists named conditions: [@@@@scopes [ \
                            (\"available\", \"status = 'available'\") ]]")
                   (List.find_opt
                      (fun (attribute : attribute) ->
                        String.equal attribute.attr_name.txt "scopes")
                      (List.concat_map
                         (fun (declaration : type_declaration) ->
                           declaration.ptype_attributes)
                         declarations))
                @ Option.fold ~none:[]
                    ~some:(fun (label : label_declaration) ->
                      [ (Labelled "prune", estring ~loc label.pld_name.txt) ])
                    (List.find_opt (fun label -> has label "prune") labels)
                @ [
                    (Labelled "name", estring ~loc table_name);
                    (Nolabel, elist ~loc (List.map fst columns));
                  ])]];
        [%stri
          let [%p pvar ~loc (value_name "for_insert")] =
            [%e
              spread
                (List.map
                   (fun label ->
                     ( label,
                       match managed label with
                       | Some (`Created_at | `Updated_at) -> Some now
                       | Some `Version -> Some [%expr 0L]
                       | None -> slug label ))
                   (List.filter
                      (fun label ->
                        not (has label "primary" && has label "auto"))
                      labels))]];
      ]
      @ Option.fold ~none:[]
          ~some:(fun key ->
            [
              [%stri
                let [%p pvar ~loc (value_name "for_update")] =
                  [%e
                    spread
                      (List.filter_map
                         (fun (label : label_declaration) ->
                           match managed label with
                           | Some (`Created_at | `Version) -> None
                           | Some `Updated_at -> Some (label, Some now)
                           | None -> Some (label, slug label))
                         (List.filter
                            (fun (label : label_declaration) ->
                              not
                                (String.equal label.pld_name.txt
                                   key.pld_name.txt))
                            labels)
                      @ [ (key, None) ]
                      @ List.filter_map
                          (fun label ->
                            match managed label with
                            | Some `Version -> Some (label, None)
                            | Some (`Created_at | `Updated_at) | None -> None)
                          labels)]];
            ])
          (List.find_opt (fun label -> has label "primary") labels)
      @ [
          [%stri
            let [%p pvar ~loc (value_name "of_row")] =
              [%e
                List.fold_right
                  (fun ( (label : label_declaration),
                         (_, (arg_label, _, row_type)) ) body ->
                    pexp_fun ~loc arg_label None
                      (ppat_constraint ~loc
                         (pvar ~loc label.pld_name.txt)
                         row_type)
                      body)
                  (List.combine labels columns)
                  (pexp_constraint ~loc
                     (let rec build path labels =
                        pexp_record ~loc
                          (List.map
                             (fun (label : label_declaration) ->
                               let path = path @ [ label.pld_name.txt ] in
                               ( { txt = Lident label.pld_name.txt; loc },
                                 match embedded label with
                                 | Some labels -> build path labels
                                 | None ->
                                     List.assoc path
                                       (List.map2
                                          (fun (path, _) (_, (_, converted, _))
                                             -> (path, converted))
                                          fields columns) ))
                             labels)
                          None
                      in
                      build [] (List.assoc type_name records))
                     (ptyp_constr ~loc { txt = Lident type_name; loc } []))]];
        ]

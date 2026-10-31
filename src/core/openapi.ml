let document ~title ~version specs =
  let component (value : Spec.value) =
    match value.module_ with
    | name
      when String.exists (fun c -> c = ' ' || c = '(') name
           || String.starts_with ~prefix:"Forge_shared." name ->
        None
    | name -> Some name
  in
  let schema (value : Spec.value) =
    Option.fold ~none:value.schema
      ~some:(fun name ->
        `Assoc [ ("$ref", `String ("#/components/schemas/" ^ name)) ])
      (component value)
  in
  let content media schema =
    `Assoc [ (media, `Assoc [ ("schema", schema) ]) ]
  in
  let operation (spec : Spec.t) (route : Spec.route) =
    let status = string_of_int (Dream.status_to_int route.status) in
    `Assoc
      ([
         ( "operationId",
           `String
             (String.concat "_"
                (List.filter (( <> ) "") (String.split_on_char '/' spec.prefix))
             ^ "_" ^ route.name) );
         ("tags", `List [ `String spec.prefix ]);
         ( "parameters",
           `List
             (List.map
                (fun (param : Spec.param) ->
                  let location, required, schema =
                    match param.location with
                    | Path -> ("path", true, schema param.value)
                    | Query Required -> ("query", true, schema param.value)
                    | Query Optional -> ("query", false, schema param.value)
                    | Query Repeated ->
                        ( "query",
                          false,
                          `Assoc
                            [
                              ("type", `String "array");
                              ("items", schema param.value);
                            ] )
                  in
                  `Assoc
                    [
                      ("name", `String param.name);
                      ("in", `String location);
                      ("required", `Bool required);
                      ("schema", schema);
                    ])
                route.params) );
         ( "responses",
           `Assoc
             [
               ( status,
                 `Assoc
                   (("description", `String route.name)
                   ::
                   (match route.returns with
                   | Unit | Raw -> []
                   | Text ->
                       [
                         ( "content",
                           content "text/plain"
                             (`Assoc [ ("type", `String "string") ]) );
                       ]
                   | Json value ->
                       [
                         ("content", content "application/json" (schema value));
                       ])) );
               ( "default",
                 `Assoc
                   [
                     ("description", `String "Problem Details (RFC 9457)");
                     ( "content",
                       content "application/problem+json"
                         (`Assoc
                            [ ("$ref", `String "#/components/schemas/Problem") ])
                     );
                   ] );
             ] );
       ]
      @ Option.fold ~none:[]
          ~some:(fun body ->
            [
              ( "requestBody",
                `Assoc
                  [
                    ("required", `Bool true);
                    ("content", content "application/json" (schema body));
                  ] );
            ])
          route.body)
  in
  let routes =
    List.concat_map
      (fun (spec : Spec.t) ->
        List.map (fun (route : Spec.route) -> (spec, route)) spec.routes)
      specs
  in
  let paths =
    List.fold_left
      (fun paths ((spec : Spec.t), (route : Spec.route)) ->
        let path =
          String.concat "/"
            (List.map
               (fun segment ->
                 match String.split_on_char ':' segment with
                 | [ ""; name ] -> "{" ^ name ^ "}"
                 | _ -> segment)
               (String.split_on_char '/' route.path))
        in
        let entry =
          ( String.lowercase_ascii (Dream.method_to_string route.verb),
            operation spec route )
        in
        match List.assoc_opt path paths with
        | None -> paths @ [ (path, [ entry ]) ]
        | Some entries ->
            List.map
              (function
                | known, _ when String.equal known path ->
                    (known, entries @ [ entry ])
                | other -> other)
              paths)
      [] routes
  in
  let components =
    List.sort_uniq compare
      (List.concat_map
         (fun ((_ : Spec.t), (route : Spec.route)) ->
           List.filter_map
             (fun (value : Spec.value) ->
               Option.map (fun name -> (name, value.schema)) (component value))
             (Option.to_list route.body
             @ List.map (fun (param : Spec.param) -> param.value) route.params
             @
             match route.returns with
             | Json value -> [ value ]
             | Unit | Text | Raw -> []))
         routes)
  in
  `Assoc
    [
      ("openapi", `String "3.1.0");
      ("info", `Assoc [ ("title", `String title); ("version", `String version) ]);
      ( "paths",
        `Assoc
          (List.map (fun (path, operations) -> (path, `Assoc operations)) paths)
      );
      ( "components",
        `Assoc
          [
            ( "schemas",
              `Assoc
                (( "Problem",
                   `Assoc
                     [
                       ("type", `String "object");
                       ( "properties",
                         `Assoc
                           [
                             ("type", `Assoc [ ("type", `String "string") ]);
                             ("title", `Assoc [ ("type", `String "string") ]);
                             ("status", `Assoc [ ("type", `String "integer") ]);
                             ("detail", `Assoc [ ("type", `String "string") ]);
                             ("instance", `Assoc [ ("type", `String "string") ]);
                           ] );
                       ( "required",
                         `List
                           [ `String "type"; `String "title"; `String "status" ]
                       );
                     ] )
                :: components) );
          ] );
    ]

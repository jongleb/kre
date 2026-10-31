open Ppxlib
open Ast_builder.Default

(** How a provider is built. *)
type construction =
  | Singleton  (** The file module itself. *)
  | Generative  (** [module Make () = …]: one fresh instance. *)
  | Factory of (string * string) list
      (** [module Make (A : I.S) …]: parameter names and the interfaces they
          need. *)

(** Which of several providers of one interface the wiring picks. *)
type rank = Primary | Secondary

type provider = {
  name : string;
  provides : string;
  construction : construction;
  hooks : string list;
      (** [on_start] and/or [on_shutdown] defined by the provider. *)
  listeners : (string * expression) list;
      (** Functions marked [[@@on_event topic]]. *)
  checks : (string * string) list;
      (** Functions marked [[@@health "name"]], with that name. *)
  jobs : (string * expression) list;
      (** Functions marked [[@@cron]], [[@@interval]] or [[@@after]], with their
          timing. *)
  rank : rank;
  loc : location;
}

type controller = { module_name : string; needs : string list; site : location }

(** What one source file contributes to the wiring. *)
type component = Provider of provider | Controller of controller | Plain

let scan path =
  let interface (module_type : module_type) =
    match module_type.pmty_desc with
    | Pmty_ident { txt; _ }
    | Pmty_with ({ pmty_desc = Pmty_ident { txt; _ }; _ }, _) ->
        Some (Longident.name txt)
    | _ -> None
  in
  let package (type_ : core_type) =
    match type_.ptyp_desc with
    | Ptyp_package ({ txt; _ }, _) -> Some (Longident.name txt)
    | _ -> None
  in
  let source = In_channel.with_open_bin path In_channel.input_all in
  let lexbuf = Lexing.from_string source in
  Lexing.set_filename lexbuf path;
  let structure = Parse.implementation lexbuf in
  let name =
    String.capitalize_ascii (Filename.remove_extension (Filename.basename path))
  in
  let floating attribute_name =
    List.find_map
      (fun (item : structure_item) ->
        match item.pstr_desc with
        | Pstr_attribute attribute
          when String.equal attribute.attr_name.txt attribute_name ->
            Some attribute
        | _ -> None)
      structure
  in
  let hooks items =
    List.filter_map
      (fun (item : structure_item) ->
        match item.pstr_desc with
        | Pstr_value (_, bindings) ->
            List.find_map
              (fun (binding : value_binding) ->
                match binding.pvb_pat.ppat_desc with
                | Ppat_var { txt = ("on_start" | "on_shutdown") as hook; _ } ->
                    Some hook
                | _ -> None)
              bindings
        | _ -> None)
      items
  in
  let make =
    List.find_map
      (fun (item : structure_item) ->
        match item.pstr_desc with
        | Pstr_module { pmb_name = { txt = Some "Make"; _ }; pmb_expr; _ } ->
            Some pmb_expr
        | _ -> None)
      structure
  in
  let rec result (module_type : module_type) =
    match module_type.pmty_desc with
    | Pmty_functor (_, body) -> result body
    | Pmty_signature items ->
        List.find_map
          (fun (item : signature_item) ->
            match item.psig_desc with
            | Psig_include { pincl_mod; _ } -> interface pincl_mod
            | _ -> None)
          items
    | _ -> interface module_type
  in
  let rec parameters (module_ : module_expr) =
    match module_.pmod_desc with
    | Pmod_functor (Unit, body) -> (`Generative, body)
    | Pmod_functor (Named ({ txt = Some parameter; _ }, module_type), body) -> (
        match (interface module_type, parameters body) with
        | Some needed, (`Factory rest, inner) ->
            (`Factory ((parameter, needed) :: rest), inner)
        | Some needed, (`Generative, inner) ->
            (`Factory [ (parameter, needed) ], inner)
        | None, _ ->
            Location.raise_errorf ~loc:module_type.pmty_loc
              "a provider's dependencies are named module types, e.g. (Db : \
               Forge.Db.S)")
    | Pmod_functor (Named ({ txt = None; loc }, _), _) ->
        Location.raise_errorf ~loc "name the dependency: (Db : Forge.Db.S)"
    | _ -> (`Factory [], module_)
  in
  let rec constraint_ (module_ : module_expr) =
    match module_.pmod_desc with
    | Pmod_functor (_, body) -> constraint_ body
    | Pmod_constraint (_, module_type) -> result module_type
    | _ -> None
  in
  let declared =
    let interface_file = Filename.remove_extension path ^ ".mli" in
    if not (Sys.file_exists interface_file) then None
    else
      let lexbuf =
        Lexing.from_string
          (In_channel.with_open_bin interface_file In_channel.input_all)
      in
      Lexing.set_filename lexbuf interface_file;
      List.find_map
        (fun (item : signature_item) ->
          match item.psig_desc with
          | Psig_module { pmd_name = { txt = Some "Make"; _ }; pmd_type; _ } ->
              result pmd_type
          | _ -> None)
        (Parse.interface lexbuf)
  in
  let own =
    List.find_map
      (fun (item : structure_item) ->
        match item.pstr_desc with
        | Pstr_modtype { pmtd_name = { txt = "S"; _ }; _ } -> Some (name ^ ".S")
        | _ -> None)
      structure
  in
  let explicit =
    Option.map
      (fun (attribute : attribute) ->
        match attribute.attr_payload with
        | PStr [] -> name ^ ".S"
        | PStr
            [
              {
                pstr_desc =
                  Pstr_eval ({ pexp_desc = Pexp_ident { txt; _ }; _ }, _);
                _;
              };
            ] ->
            Longident.name txt
        | _ ->
            Location.raise_errorf ~loc:attribute.attr_loc
              "[@@@@@@injectable] takes nothing or the interface it provides, \
               e.g. [@@@@@@injectable Cats_service.S]")
      (floating "injectable")
  in
  let site =
    match structure with
    | first :: _ -> first.pstr_loc
    | [] -> Location.in_file path
  in
  match
    Option.fold ~none:(floating "gateway") ~some:Option.some
      (floating "controller")
  with
  | Some attribute ->
      Controller
        {
          module_name = name;
          site = attribute.attr_loc;
          needs =
            List.fold_left
              (fun needs (item : structure_item) ->
                match item.pstr_desc with
                | Pstr_value (_, bindings) ->
                    List.fold_left
                      (fun needs (binding : value_binding) ->
                        match binding.pvb_expr.pexp_desc with
                        | Pexp_function (params, _, _)
                          when List.exists
                                 (fun (attribute : attribute) ->
                                   List.mem attribute.attr_name.txt
                                     [
                                       "get";
                                       "post";
                                       "put";
                                       "patch";
                                       "delete";
                                       "head";
                                       "options";
                                       "all";
                                       "subscribe";
                                     ])
                                 binding.pvb_attributes ->
                            List.fold_left
                              (fun needs (param : function_param) ->
                                match param.pparam_desc with
                                | Pparam_val
                                    ( Nolabel,
                                      _,
                                      {
                                        ppat_desc =
                                          Ppat_constraint
                                            ( { ppat_desc = Ppat_unpack _; _ },
                                              type_ );
                                        _;
                                      } ) -> (
                                    match package type_ with
                                    | Some needed
                                      when not (List.mem needed needs) ->
                                        needs @ [ needed ]
                                    | Some _ | None -> needs)
                                | _ -> needs)
                              needs params
                        | _ -> needs)
                      needs bindings
                | _ -> needs)
              [] structure;
        }
  | None -> (
      let provides =
        match (explicit, make) with
        | Some provides, _ -> Some provides
        | None, Some make ->
            Option.map
              (fun found ->
                match String.index_opt found '.' with
                | Some _ -> found
                | None -> name ^ "." ^ found)
              (List.find_map Fun.id [ constraint_ make; declared; own ])
        | None, None -> own
      in
      match provides with
      | None -> Plain
      | Some provides ->
          let construction, body =
            match make with
            | None -> (Singleton, pmod_structure ~loc:site structure)
            | Some make -> (
                match parameters make with
                | `Generative, body -> (Generative, body)
                | `Factory [], body -> (Singleton, body)
                | `Factory needs, body -> (Factory needs, body))
          in
          let rec items (module_ : module_expr) =
            match module_.pmod_desc with
            | Pmod_structure items -> items
            | Pmod_constraint (inner, _) -> items inner
            | _ -> []
          in
          Provider
            {
              name;
              provides;
              construction;
              hooks = hooks (items body);
              checks =
                List.concat_map
                  (fun (item : structure_item) ->
                    match item.pstr_desc with
                    | Pstr_value (_, bindings) ->
                        List.filter_map
                          (fun (binding : value_binding) ->
                            match
                              ( binding.pvb_pat.ppat_desc,
                                List.find_map
                                  (fun (attribute : attribute) ->
                                    match
                                      ( attribute.attr_name.txt,
                                        attribute.attr_payload )
                                    with
                                    | ( "health",
                                        PStr
                                          [
                                            {
                                              pstr_desc =
                                                Pstr_eval
                                                  ( {
                                                      pexp_desc =
                                                        Pexp_constant
                                                          (Pconst_string
                                                             (check, _, _));
                                                      _;
                                                    },
                                                    _ );
                                              _;
                                            };
                                          ] ) ->
                                        Some check
                                    | "health", _ ->
                                        Location.raise_errorf
                                          ~loc:attribute.attr_loc
                                          "[@@health] takes the check's name: \
                                           [@@health \"db\"]"
                                    | _ -> None)
                                  binding.pvb_attributes )
                            with
                            | Ppat_var { txt; _ }, Some check ->
                                Some (txt, check)
                            | _ -> None)
                          bindings
                    | _ -> [])
                  (items body);
              jobs =
                List.concat_map
                  (fun (item : structure_item) ->
                    match item.pstr_desc with
                    | Pstr_value (_, bindings) ->
                        List.filter_map
                          (fun (binding : value_binding) ->
                            match binding.pvb_pat.ppat_desc with
                            | Ppat_var { txt; _ } ->
                                Option.map
                                  (fun timing -> (txt, timing))
                                  (List.find_map
                                     (fun (attribute : attribute) ->
                                       let loc = attribute.attr_loc in
                                       let payload () =
                                         match attribute.attr_payload with
                                         | PStr
                                             [
                                               {
                                                 pstr_desc =
                                                   Pstr_eval (expression, _);
                                                 _;
                                               };
                                             ] ->
                                             expression
                                         | _ ->
                                             Location.raise_errorf ~loc
                                               "[@@%s] needs a value"
                                               attribute.attr_name.txt
                                       in
                                       let seconds () =
                                         match (payload ()).pexp_desc with
                                         | Pexp_constant (Pconst_float _) ->
                                             payload ()
                                         | _ ->
                                             Location.raise_errorf ~loc
                                               "[@@%s] takes seconds as a \
                                                float, e.g. [@@%s 30.0]"
                                               attribute.attr_name.txt
                                               attribute.attr_name.txt
                                       in
                                       match attribute.attr_name.txt with
                                       | "cron" -> (
                                           match (payload ()).pexp_desc with
                                           | Pexp_constant
                                               (Pconst_string (expression, _, _))
                                             -> (
                                               match
                                                 Forge_shared.Cron.of_string
                                                   expression
                                               with
                                               | Ok _ ->
                                                   Some
                                                     [%expr
                                                       Forge.Schedule.Cron
                                                         (Forge_shared.Cron
                                                          .of_string_exn
                                                            [%e
                                                              estring ~loc
                                                                expression])]
                                               | Error message ->
                                                   Location.raise_errorf ~loc
                                                     "[@@cron %S]: %s"
                                                     expression message)
                                           | _ ->
                                               Location.raise_errorf ~loc
                                                 "[@@cron] takes a cron \
                                                  string, e.g. [@@cron \"0 3 * \
                                                  * *\"]")
                                       | "interval" ->
                                           Some
                                             [%expr
                                               Forge.Schedule.Every
                                                 [%e seconds ()]]
                                       | "after" ->
                                           Some
                                             [%expr
                                               Forge.Schedule.After
                                                 [%e seconds ()]]
                                       | _ -> None)
                                     binding.pvb_attributes)
                            | _ -> None)
                          bindings
                    | _ -> [])
                  (items body);
              listeners =
                List.concat_map
                  (fun (item : structure_item) ->
                    match item.pstr_desc with
                    | Pstr_value (_, bindings) ->
                        List.filter_map
                          (fun (binding : value_binding) ->
                            match
                              ( binding.pvb_pat.ppat_desc,
                                List.find_map
                                  (fun (attribute : attribute) ->
                                    match
                                      ( attribute.attr_name.txt,
                                        attribute.attr_payload )
                                    with
                                    | ( "on_event",
                                        PStr
                                          [
                                            {
                                              pstr_desc = Pstr_eval (topic, _);
                                              _;
                                            };
                                          ] ) ->
                                        Some topic
                                    | _ -> None)
                                  binding.pvb_attributes )
                            with
                            | Ppat_var { txt; _ }, Some topic ->
                                Some (txt, topic)
                            | _ -> None)
                          bindings
                    | _ -> [])
                  (items body);
              rank =
                Option.fold ~none:Secondary
                  ~some:(fun _ -> Primary)
                  (floating "primary");
              loc = site;
            })

let expand ~loc ~input directories =
  let application = Filename.dirname (Filename.dirname input) in
  let rec sources directory =
    List.concat_map
      (fun entry ->
        let path = Filename.concat directory entry in
        match entry with
        | "_build" | "node_modules" | "test" | "tests" -> []
        | entry when String.starts_with ~prefix:"." entry -> []
        | _ when Sys.is_directory path -> sources path
        | entry
          when Filename.check_suffix entry ".ml"
               && not (Filename.check_suffix entry ".pp.ml") ->
            [ path ]
        | _ -> [])
      (List.sort String.compare (Array.to_list (Sys.readdir directory)))
  in
  let components =
    List.fold_left
      (fun (seen, components) path ->
        let name =
          String.capitalize_ascii
            (Filename.remove_extension (Filename.basename path))
        in
        if List.mem name seen then (seen, components)
        else (name :: seen, components @ [ scan path ]))
      ([], [])
      (List.concat_map
         (fun directory -> sources (Filename.concat application directory))
         (match directories with [] -> [ "." ] | directories -> directories))
    |> snd
  in
  let providers =
    List.filter_map
      (function
        | Provider provider -> Some provider | Controller _ | Plain -> None)
      components
  in
  let controllers =
    List.filter_map
      (function
        | Controller controller -> Some controller | Provider _ | Plain -> None)
      components
  in
  let resolve ?parameter ~needed ~site ~by () =
    match
      List.filter
        (fun provider -> String.equal provider.provides needed)
        providers
    with
    | [ provider ] -> provider
    | [] ->
        Location.raise_errorf ~loc:site
          "%s needs %s, but no provider gives it: add a module with Make or \
           module type S that implements it"
          by needed
    | candidates -> (
        match
          ( List.filter
              (fun provider ->
                match provider.rank with Primary -> true | Secondary -> false)
              candidates,
            Option.bind parameter (fun parameter ->
                List.find_opt
                  (fun provider -> String.equal provider.name parameter)
                  candidates) )
        with
        | [ provider ], _ -> provider
        | ([] | _ :: _ :: _), Some named -> named
        | _ ->
            Location.raise_errorf ~loc:site
              "%s needs %s and %d providers give it (%s); mark one \
               [@@@@@@primary] or name the parameter after one"
              by needed (List.length candidates)
              (String.concat ", "
                 (List.map (fun provider -> provider.name) candidates)))
  in
  let order =
    let same provider other = String.equal provider.name other.name in
    let rec visit path order provider =
      if List.exists (same provider) order then order
      else if List.mem provider.name path then
        Location.raise_errorf ~loc:provider.loc "dependency cycle: %s"
          (String.concat " -> " (List.rev (provider.name :: path)))
      else
        let order =
          List.fold_left
            (fun order (parameter, needed) ->
              visit (provider.name :: path) order
                (resolve ~parameter ~needed ~site:provider.loc ~by:provider.name
                   ()))
            order
            (match provider.construction with
            | Factory needs -> needs
            | Singleton | Generative -> [])
        in
        if List.exists (same provider) order then order
        else order @ [ provider ]
    in
    List.fold_left (visit []) [] providers
  in
  let instance provider = pmod_ident ~loc { txt = Lident provider.name; loc } in
  let hooks name =
    elist ~loc
      (List.filter_map
         (fun provider ->
           Option.map
             (fun hook ->
               pexp_ident ~loc { txt = Ldot (Lident provider.name, hook); loc })
             (List.find_opt (String.equal name) provider.hooks))
         order)
  in
  let subscriptions =
    List.concat_map
      (fun provider ->
        List.map
          (fun (listener, topic) ->
            let bus =
              resolve ~needed:"Forge.Events.S" ~site:provider.loc
                ~by:provider.name ()
            in
            [%expr
              [%e
                pexp_ident ~loc
                  { txt = Ldot (Lident bus.name, "subscribe"); loc }]
                [%e topic]
                [%e
                  pexp_ident ~loc
                    { txt = Ldot (Lident provider.name, listener); loc }]])
          provider.listeners)
      order
  in
  let wiring =
    [%expr
      Forge.Wiring.make
        ~controllers:
          [%e
            elist ~loc
              (List.map
                 (fun controller ->
                   pexp_apply ~loc
                     (pexp_ident ~loc
                        {
                          txt = Ldot (Lident controller.module_name, "register");
                          loc;
                        })
                     (match controller.needs with
                     | [] -> [ (Nolabel, [%expr ()]) ]
                     | needs ->
                         List.map
                           (fun needed ->
                             ( Nolabel,
                               pexp_pack ~loc
                                 (instance
                                    (resolve ~needed ~site:controller.site
                                       ~by:controller.module_name ())) ))
                           needs))
                 controllers)]
        ~on_start:[%e hooks "on_start"] ~on_shutdown:[%e hooks "on_shutdown"]
        ~jobs:
          [%e
            elist ~loc
              (List.concat_map
                 (fun provider ->
                   List.map
                     (fun (job, timing) ->
                       [%expr
                         Forge.Schedule.job
                           ~name:[%e estring ~loc (provider.name ^ "." ^ job)]
                           [%e timing]
                           [%e
                             pexp_ident ~loc
                               { txt = Ldot (Lident provider.name, job); loc }]])
                     provider.jobs)
                 order)]
        ~health:
          [%e
            elist ~loc
              (List.concat_map
                 (fun provider ->
                   List.map
                     (fun (check, name) ->
                       [%expr
                         {
                           Forge.Actuator.name = [%e estring ~loc name];
                           run =
                             [%e
                               pexp_ident ~loc
                                 {
                                   txt = Ldot (Lident provider.name, check);
                                   loc;
                                 }];
                         }])
                     provider.checks)
                 order)]
        ()]
  in
  let wiring =
    List.fold_right
      (fun subscription rest -> pexp_sequence ~loc subscription rest)
      subscriptions wiring
  in
  List.fold_right
    (fun provider body ->
      match provider.construction with
      | Singleton -> body
      | Generative ->
          pexp_letmodule ~loc
            { txt = Some provider.name; loc }
            (pmod_apply_unit ~loc
               (pmod_ident ~loc
                  { txt = Ldot (Lident provider.name, "Make"); loc }))
            body
      | Factory needs ->
          pexp_letmodule ~loc
            { txt = Some provider.name; loc }
            (List.fold_left
               (fun functor_ (parameter, needed) ->
                 pmod_apply ~loc functor_
                   (instance
                      (resolve ~parameter ~needed ~site:provider.loc
                         ~by:provider.name ())))
               (pmod_ident ~loc
                  { txt = Ldot (Lident provider.name, "Make"); loc })
               needs)
            body)
    order wiring

let extension =
  Extension.V3.declare "wire" Extension.Context.expression
    Ast_pattern.(pstr __)
    (fun ~ctxt items ->
      let loc = Expansion_context.Extension.extension_point_loc ctxt in
      let directories =
        List.concat_map
          (fun (item : structure_item) ->
            match item.pstr_desc with
            | Pstr_eval (expression, _) ->
                let rec strings (expression : expression) =
                  match expression.pexp_desc with
                  | Pexp_constant (Pconst_string (directory, _, _)) ->
                      [ directory ]
                  | Pexp_sequence (first, rest) -> strings first @ strings rest
                  | _ ->
                      Location.raise_errorf ~loc:expression.pexp_loc
                        "[%%wire] scans the application directory; to narrow \
                         it, list subdirectories: [%%wire \"server\"; \"db\"]"
                in
                strings expression
            | _ ->
                Location.raise_errorf ~loc
                  "[%%wire] scans the application directory; to narrow it, \
                   list subdirectories: [%%wire \"server\"; \"db\"]")
          items
      in
      expand ~loc
        ~input:(Expansion_context.Extension.input_name ctxt)
        directories)

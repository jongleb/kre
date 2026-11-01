open Ppxlib
open Ast_builder.Default

(** What a functor parameter asks for. *)
type need =
  | One of string  (** The provider of this interface. *)
  | Every of string
      (** All providers of this interface, as a [Kre.Wiring.ALL] module. *)

(** How a provider is built. *)
type construction =
  | Singleton  (** The file module itself. *)
  | Generative  (** [module Make () = …]: one fresh instance. *)
  | Factory of (string * need) list
      (** [module Make (A : I.S) …]: parameter names and what they need. *)

(** Which of several providers of one interface the wiring picks. *)
type rank =
  | Primary
  | Secondary
  | Fallback  (** Used only when nothing else provides the interface. *)
  | Decorator
      (** [[@@@decorates I.S]]: wraps the provider of its interface; everyone
          else gets the wrapper. *)

type provider = {
  name : string;
  provides : string;
  construction : construction;
  hooks : string list;
      (** [on_start] and/or [on_shutdown] defined by the provider. *)
  listeners : (string * expression) list;
      (** Functions marked [[@@on_event topic]]. *)
  performs : (string * expression) list;
      (** Functions marked [[@@job queue]]. *)
  checks : (string * string) list;
      (** Functions marked [[@@health "name"]], with that name. *)
  jobs : (string * expression) list;
      (** Functions marked [[@@cron]], [[@@interval]] or [[@@after]], with their
          timing. *)
  rank : rank;
  profile : string option;
      (** [[@@@profile "dev"]]: used instead of the provider without a profile
          when [KRE_ENV] is this. *)
  loc : location;
}

type controller = { module_name : string; needs : string list; site : location }

type tasks = {
  file : string;
  commands : (string * string list) list;
      (** [[@@command]] functions with the interfaces they take. *)
  at : location;
}
(** A file of commands. *)

(** What one source file contributes to the wiring. *)
type component =
  | Provider of provider
  | Controller of controller
  | Tasks of tasks
  | Plain

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
  let structure = Resource.structure (Parse.implementation lexbuf) in
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
        let need =
          match (module_type.pmty_desc, interface module_type) with
          | ( Pmty_with
                (_, [ Pwith_type (_, { ptype_manifest = Some type_; _ }) ]),
              Some "Kre.Wiring.ALL" ) ->
              Option.map (fun needed -> Every needed) (package type_)
          | _, Some "Kre.Wiring.ALL" -> None
          | _, needed -> Option.map (fun needed -> One needed) needed
        in
        match (need, parameters body) with
        | Some needed, (`Factory rest, inner) ->
            (`Factory ((parameter, needed) :: rest), inner)
        | Some needed, (`Generative, inner) ->
            (`Factory [ (parameter, needed) ], inner)
        | None, _ ->
            Location.raise_errorf ~loc:module_type.pmty_loc
              "a provider's dependencies are named module types, e.g. (Db : \
               Kre.Db.S), or every provider of one: (All : Kre.Wiring.ALL with \
               type t = (module Notifier.S))")
    | Pmod_functor (Named ({ txt = None; loc }, _), _) ->
        Location.raise_errorf ~loc "name the dependency: (Db : Kre.Db.S)"
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
    let named (attribute : attribute) =
      match attribute.attr_payload with
      | PStr [] -> None
      | PStr
          [
            {
              pstr_desc =
                Pstr_eval
                  ( {
                      pexp_desc =
                        Pexp_ident { txt; _ } | Pexp_construct ({ txt; _ }, None);
                      _;
                    },
                    _ );
              _;
            };
          ] ->
          Some (Longident.name txt)
      | _ ->
          Location.raise_errorf ~loc:attribute.attr_loc
            "[@@@@@@%s] takes the interface, e.g. [@@@@@@%s Cats_service.S]"
            attribute.attr_name.txt attribute.attr_name.txt
    in
    match (floating "decorates", floating "injectable") with
    | Some attribute, _ -> (
        match named attribute with
        | Some wrapped -> Some wrapped
        | None ->
            Location.raise_errorf ~loc:attribute.attr_loc
              "[@@@@@@decorates] names the interface it wraps: \
               [@@@@@@decorates Clock.S]")
    | None, Some attribute ->
        Some (Option.value (named attribute) ~default:(name ^ ".S"))
    | None, None -> None
  in
  let site =
    match structure with
    | first :: _ -> first.pstr_loc
    | [] -> Location.in_file path
  in
  let commands =
    List.concat_map
      (fun (item : structure_item) ->
        match item.pstr_desc with
        | Pstr_value (_, bindings) ->
            List.filter_map
              (fun (binding : value_binding) ->
                match
                  ( binding.pvb_pat.ppat_desc,
                    binding.pvb_expr.pexp_desc,
                    List.find_opt
                      (fun (attribute : attribute) ->
                        String.equal attribute.attr_name.txt "command")
                      binding.pvb_attributes )
                with
                | Ppat_var { txt; _ }, Pexp_function (params, _, _), Some _ ->
                    Some
                      ( txt,
                        List.filter_map
                          (fun (param : function_param) ->
                            match param.pparam_desc with
                            | Pparam_val
                                ( Nolabel,
                                  _,
                                  {
                                    ppat_desc =
                                      Ppat_constraint
                                        ({ ppat_desc = Ppat_unpack _; _ }, type_);
                                    _;
                                  } ) ->
                                package type_
                            | _ -> None)
                          params )
                | _ -> None)
              bindings
        | _ -> [])
      structure
  in
  let component =
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
              ( List.fold_left
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
                                                ( {
                                                    ppat_desc = Ppat_unpack _;
                                                    _;
                                                  },
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
                  [] structure
              |> fun needs ->
                match
                  ( List.find_map
                      (fun (item : structure_item) ->
                        match item.pstr_desc with
                        | Pstr_value (_, bindings) ->
                            List.find_map
                              (fun (binding : value_binding) ->
                                List.find_opt
                                  (fun (attribute : attribute) ->
                                    String.equal attribute.attr_name.txt
                                      "ability")
                                  binding.pvb_attributes)
                              bindings
                        | _ -> None)
                      structure,
                    List.find_opt (String.equal "Kre.Token.S") needs )
                with
                | Some _, None -> needs @ [ "Kre.Token.S" ]
                | Some _, Some _ | None, _ -> needs );
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
          | None, None ->
              Option.bind own (fun own ->
                  List.find_map
                    (fun (item : structure_item) ->
                      match item.pstr_desc with
                      | Pstr_value _ -> Some own
                      | _ -> None)
                    structure)
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
                hooks =
                  (match provides with
                  | "Kre.Job.S" -> [ "on_start"; "on_shutdown" ]
                  | _ -> hooks (items body));
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
                                            "[@@health] takes the check's \
                                             name: [@@health \"db\"]"
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
                                                 (Pconst_string
                                                    (expression, _, _)) -> (
                                                 match
                                                   Kre_shared.Cron.of_string
                                                     expression
                                                 with
                                                 | Ok _ ->
                                                     Some
                                                       [%expr
                                                         Kre.Schedule.Cron
                                                           (Kre_shared.Cron
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
                                                    string, e.g. [@@cron \"0 3 \
                                                    * * *\"]")
                                         | "interval" ->
                                             Some
                                               [%expr
                                                 Kre.Schedule.Every
                                                   [%e seconds ()]]
                                         | "after" ->
                                             Some
                                               [%expr
                                                 Kre.Schedule.After
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
                performs =
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
                                      | ( "job",
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
                  (match
                     ( floating "decorates",
                       floating "primary",
                       floating "fallback" )
                   with
                  | Some _, _, _ -> Decorator
                  | None, Some _, _ -> Primary
                  | None, None, Some _ -> Fallback
                  | None, None, None -> Secondary);
                profile =
                  Option.map
                    (fun (attribute : attribute) ->
                      match attribute.attr_payload with
                      | PStr
                          [
                            {
                              pstr_desc =
                                Pstr_eval
                                  ( {
                                      pexp_desc =
                                        Pexp_constant
                                          (Pconst_string (profile, _, _));
                                      _;
                                    },
                                    _ );
                              _;
                            };
                          ] ->
                          profile
                      | _ ->
                          Location.raise_errorf ~loc:attribute.attr_loc
                            "[@@@@@@profile] takes the KRE_ENV value it is \
                             used for: [@@@@@@profile \"dev\"]")
                    (floating "profile");
                loc = site;
              })
  in
  match (component, commands) with
  | _, [] -> component
  | Plain, commands -> Tasks { file = name; commands; at = site }
  | (Provider _ | Controller _ | Tasks _), (command, _) :: _ ->
      Location.raise_errorf ~loc:site
        "%s is a provider or controller, so [%%wire] does not run its command \
         %s; move [@@@@command] functions to a file of their own"
        name command

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
  let all =
    List.filter_map
      (function
        | Provider provider -> Some provider
        | Controller _ | Tasks _ | Plain -> None)
      components
  in
  let active =
    List.filter
      (fun provider ->
        match provider.rank with
        | Primary | Secondary | Decorator -> true
        | Fallback ->
            not
              (List.exists
                 (fun other ->
                   String.equal other.provides provider.provides
                   && Option.is_none other.profile
                   &&
                   match other.rank with
                   | Primary | Secondary -> true
                   | Fallback | Decorator -> false)
                 all))
      all
  in
  let providers =
    List.filter (fun provider -> Option.is_none provider.profile) active
  in
  let controllers =
    List.filter_map
      (function
        | Controller controller -> Some controller
        | Provider _ | Tasks _ | Plain -> None)
      components
  in
  let tasks =
    List.filter_map
      (function
        | Tasks tasks -> Some tasks | Provider _ | Controller _ | Plain -> None)
      components
  in
  let choose ?parameter ~needed ~site ~by () =
    match
      List.filter
        (fun provider ->
          String.equal provider.provides needed
          &&
          match provider.rank with
          | Decorator -> false
          | Primary | Secondary | Fallback -> true)
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
                match provider.rank with
                | Primary -> true
                | Secondary | Fallback | Decorator -> false)
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
  let resolve ?parameter ~needed ~site ~by () =
    let decorators =
      List.filter
        (fun provider ->
          String.equal provider.provides needed
          &&
          match provider.rank with
          | Decorator -> true
          | Primary | Secondary | Fallback -> false)
        providers
    in
    match
      ( List.find_index
          (fun decorator -> String.equal decorator.name by)
          decorators,
        List.rev decorators )
    with
    | Some position, _ when position > 0 -> List.nth decorators (position - 1)
    | None, outermost :: _ -> outermost
    | Some _, _ | None, [] -> choose ?parameter ~needed ~site ~by ()
  in
  let every ~needed ~by =
    List.filter
      (fun provider ->
        String.equal provider.provides needed
        && (not (String.equal provider.name by))
        &&
        match provider.rank with
        | Decorator -> false
        | Primary | Secondary | Fallback -> true)
      providers
  in
  let dependencies provider =
    match provider.construction with
    | Factory needs ->
        List.concat_map
          (fun (parameter, need) ->
            match need with
            | One needed ->
                [
                  resolve ~parameter ~needed ~site:provider.loc
                    ~by:provider.name ();
                ]
            | Every needed -> every ~needed ~by:provider.name)
          needs
    | Singleton | Generative -> []
  in
  let variants =
    List.fold_left
      (fun variants variant ->
        match (variant.profile, variant.rank) with
        | None, _ -> variants
        | Some profile, Decorator ->
            Location.raise_errorf ~loc:variant.loc
              "%s decorates %s and has [@@@@@@profile %S]; a decorator wraps \
               every environment, so drop the profile"
              variant.name variant.provides profile
        | Some profile, (Primary | Secondary | Fallback) -> (
            let default =
              match
                List.filter
                  (fun provider ->
                    String.equal provider.provides variant.provides)
                  providers
              with
              | [] ->
                  Location.raise_errorf ~loc:variant.loc
                    "%s has [@@@@@@profile %S], but %s has no provider without \
                     a profile for the other environments; add one"
                    variant.name profile variant.provides
              | _ :: _ ->
                  choose ~needed:variant.provides ~site:variant.loc
                    ~by:variant.name ()
            in
            match
              List.find_opt
                (fun (owner, (taken, _)) ->
                  String.equal owner default.name && String.equal taken profile)
                variants
            with
            | Some (_, (_, other)) ->
                Location.raise_errorf ~loc:variant.loc
                  "%s and %s both have [@@@@@@profile %S] for %s; keep one"
                  other.name variant.name profile variant.provides
            | None -> variants @ [ (default.name, (profile, variant)) ]))
      [] active
  in
  let variants_of provider =
    List.map snd
      (List.filter
         (fun (owner, _) -> String.equal owner provider.name)
         variants)
  in
  List.iter
    (fun provider ->
      match variants_of provider with
      | [] -> ()
      | profiled ->
          List.iter
            (fun member ->
              match
                ( member.hooks,
                  member.listeners,
                  member.performs,
                  member.checks,
                  member.jobs )
              with
              | [], [], [], [], [] -> ()
              | _ ->
                  Location.raise_errorf ~loc:member.loc
                    "%s is picked by KRE_ENV at start-up and seen only as %s, \
                     so its on_start, on_shutdown and [@@@@on_event], \
                     [@@@@job], [@@@@health] or schedule functions would never \
                     run; move them to a provider of their own"
                    member.name member.provides)
            (provider :: List.map snd profiled))
    providers;
  List.iter
    (fun provider ->
      match provider.rank with
      | Decorator -> (
          match provider.construction with
          | Factory needs
            when List.exists
                   (fun (_, need) ->
                     match need with
                     | One needed -> String.equal needed provider.provides
                     | Every _ -> false)
                   needs ->
              ()
          | Factory _ | Singleton | Generative ->
              Location.raise_errorf ~loc:provider.loc
                "%s decorates %s, so its Make takes the original: module Make \
                 (Inner : %s) = …"
                provider.name provider.provides provider.provides)
      | Primary | Secondary | Fallback -> ())
    providers;
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
            (visit (provider.name :: path))
            order
            (List.concat_map dependencies
               (provider :: List.map snd (variants_of provider)))
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
              resolve ~needed:"Kre.Events.S" ~site:provider.loc
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
  let subscriptions =
    subscriptions
    @ List.concat_map
        (fun provider ->
          List.map
            (fun (performer, queue) ->
              let jobs =
                resolve ~needed:"Kre.Job.S" ~site:provider.loc ~by:provider.name
                  ()
              in
              [%expr
                [%e
                  pexp_ident ~loc
                    { txt = Ldot (Lident jobs.name, "register"); loc }]
                  (Kre.Job.handle [%e queue]
                     [%e
                       pexp_ident ~loc
                         { txt = Ldot (Lident provider.name, performer); loc }])])
            provider.performs)
        order
  in
  let wiring =
    [%expr
      Kre.Wiring.make
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
                 controllers
              @ List.filter_map
                  (fun provider ->
                    match provider.provides with
                    | "Kre.Job.S" ->
                        Some
                          (pexp_ident ~loc
                             {
                               txt = Ldot (Lident provider.name, "dashboard");
                               loc;
                             })
                    | _ -> None)
                  order)]
        ~on_start:[%e hooks "on_start"] ~on_shutdown:[%e hooks "on_shutdown"]
        ~jobs:
          [%e
            elist ~loc
              (List.concat_map
                 (fun provider ->
                   List.map
                     (fun (job, timing) ->
                       [%expr
                         Kre.Schedule.job
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
                           Kre.Actuator.name = [%e estring ~loc name];
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
        ~commands:
          [%e
            elist ~loc
              (List.concat_map
                 (fun tasks ->
                   List.map
                     (fun (command, needs) ->
                       pexp_apply ~loc
                         (pexp_ident ~loc
                            {
                              txt =
                                Ldot
                                  (Lident tasks.file, "__kre_command_" ^ command);
                              loc;
                            })
                         (match needs with
                         | [] -> [ (Nolabel, [%expr ()]) ]
                         | needs ->
                             List.map
                               (fun needed ->
                                 ( Nolabel,
                                   pexp_pack ~loc
                                     (instance
                                        (resolve ~needed ~site:tasks.at
                                           ~by:(tasks.file ^ "." ^ command)
                                           ())) ))
                               needs))
                     tasks.commands)
                 tasks)]
        ~beans:
          [%e
            elist ~loc
              (List.map
                 (fun provider ->
                   [%expr
                     {
                       Kre.Actuator.name = [%e estring ~loc provider.name];
                       needs =
                         [%e
                           elist ~loc
                             (List.fold_left
                                (fun names dependency ->
                                  Option.fold
                                    ~none:(names @ [ dependency.name ])
                                    ~some:(fun _ -> names)
                                    (List.find_opt
                                       (String.equal dependency.name)
                                       names))
                                []
                                (List.concat_map dependencies
                                   (provider
                                   :: List.map snd (variants_of provider)))
                             |> List.map (estring ~loc))];
                     }])
                 order
              @ List.map
                  (fun controller ->
                    [%expr
                      {
                        Kre.Actuator.name =
                          [%e estring ~loc controller.module_name];
                        needs =
                          [%e
                            elist ~loc
                              (List.map
                                 (fun needed ->
                                   estring ~loc
                                     (resolve ~needed ~site:controller.site
                                        ~by:controller.module_name ())
                                       .name)
                                 controller.needs)];
                      }])
                  controllers)]
        ()]
  in
  let wiring =
    List.fold_right
      (fun subscription rest -> pexp_sequence ~loc subscription rest)
      subscriptions wiring
  in
  let package interface =
    ptyp_package ~loc ({ txt = Longident.parse interface; loc }, [])
  in
  let build provider =
    match provider.construction with
    | Singleton -> instance provider
    | Generative ->
        pmod_apply_unit ~loc
          (pmod_ident ~loc { txt = Ldot (Lident provider.name, "Make"); loc })
    | Factory needs ->
        List.fold_left
          (fun functor_ (parameter, need) ->
            pmod_apply ~loc functor_
              (match need with
              | One needed ->
                  instance
                    (resolve ~parameter ~needed ~site:provider.loc
                       ~by:provider.name ())
              | Every needed ->
                  pmod_structure ~loc
                    [
                      [%stri type t = [%t package needed]];
                      [%stri
                        let all =
                          [%e
                            elist ~loc
                              (List.map
                                 (fun member ->
                                   pexp_constraint ~loc
                                     (pexp_pack ~loc (instance member))
                                     (package needed))
                                 (every ~needed ~by:provider.name))]];
                    ]))
          (pmod_ident ~loc { txt = Ldot (Lident provider.name, "Make"); loc })
          needs
  in
  List.fold_right
    (fun provider body ->
      match (provider.construction, variants_of provider) with
      | Singleton, [] -> body
      | (Generative | Factory _), [] ->
          pexp_letmodule ~loc
            { txt = Some provider.name; loc }
            (build provider) body
      | _, profiled ->
          let packed member =
            pexp_constraint ~loc
              (pexp_pack ~loc (build member))
              (package provider.provides)
          in
          pexp_letmodule ~loc
            { txt = Some provider.name; loc }
            (pmod_unpack ~loc
               (pexp_constraint ~loc
                  (pexp_match ~loc [%expr Kre.Wiring.profile ()]
                     (List.map
                        (fun (profile, variant) ->
                          case ~lhs:(pstring ~loc profile) ~guard:None
                            ~rhs:(packed variant))
                        profiled
                     @ [
                         case ~lhs:[%pat? _] ~guard:None ~rhs:(packed provider);
                       ]))
                  (package provider.provides)))
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

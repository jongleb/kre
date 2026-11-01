open Ppxlib
open Ast_builder.Default

type verb = Get | Post | Put | Patch | Delete | Head | Options | All

type value = { type_ : core_type; module_ : module_expr }
(** A type crossing the wire and the module that converts it. *)

type presence = Required | Optional | Repeated

(** Where a decorated parameter is read from. *)
type carrier = Header | Cookie | Signed_cookie | Session | Form

(** Where one argument of a handler comes from. *)
type source =
  | Dependency of { name : string; pattern : pattern; package : core_type }
  | Path of { segment : string; value : value }
  | Query of { name : string; presence : presence; value : value }
  | Located of {
      carrier : carrier;
      name : string;
      presence : presence;
      value : value;
    }  (** [[@header]], [[@cookie]], [[@signed_cookie]], [[@session]]. *)
  | Body of value
  | Searched of value
      (** [[@search]]: the query string as a record with a search codec. *)
  | Loaded of { segment : string; value : value; loader : expression }
      (** [[@load f]]: the path segment parsed as [M.Id], then [f] finds [M.t].
      *)
  | Extracted of expression  (** [[@guard e]] or [[@from e]]. *)
  | Wildcard  (** [[@wildcard]]: what a trailing [*] matched. *)
  | Request
  | Unit

type argument = { label : arg_label; source : source; loc : location }

(** One segment of a route path. *)
type segment =
  | Literal of string
  | Param of { name : string; value : value }
  | Rest  (** A trailing [*]. *)

(** How the handler's result becomes a response. *)
type shape =
  | Empty
  | Text
  | Raw
  | Json of value
  | Found of value
  | Moved of string  (** [[@@redirect]]: an empty answer with [Location]. *)
  | Stream of value  (** [[@@sse]]: server-sent events. *)

(** [Fallible] handlers return [(_, Kre.Error.t) result Lwt.t]. *)
type outcome = Plain | Fallible

type handler = {
  name : string;
  verb : verb;
  segments : segment list;
  status : int;
  middleware : expression list;
  guards : expression list;
  arguments : argument list;
  shape : shape;
  outcome : outcome;
  headers : expression list;  (** [[@@header (name, value)]], repeatable. *)
  interceptors : expression list;  (** [[@@@intercept]] then [[@@intercept]]. *)
  error_handler : expression option;
      (** [[@@error_handler h]] on the handler. *)
  summary : string option;  (** [[@@summary]]. *)
  description : string option;  (** [[@@description]]. *)
  live : string list;  (** [[@@live ["cats"]]]: tables that reload the page. *)
  timeout : expression option;  (** [[@@timeout seconds]]. *)
  authorize : expression option;
      (** [[@@authorize f]], applied to the handler's own arguments. *)
  check : expression option;
      (** [[@@check f]]: like [authorize], its [Error] is a 422. *)
  transaction : longident option;
      (** [[@@transactional]]: the [Kre.Db.S] dependency, or [M] of
          [[@from M.tx]]. *)
}

let string_payload (attribute : attribute) =
  match attribute.attr_payload with
  | PStr [] -> ""
  | PStr
      [
        {
          pstr_desc =
            Pstr_eval
              ({ pexp_desc = Pexp_constant (Pconst_string (s, _, _)); _ }, _);
          _;
        };
      ] ->
      s
  | _ ->
      Location.raise_errorf ~loc:attribute.attr_loc
        "[@@@@%s] expects a string literal, e.g. [@@@@%s \":id\"]"
        attribute.attr_name.txt attribute.attr_name.txt

let int_payload (attribute : attribute) =
  match attribute.attr_payload with
  | PStr
      [
        {
          pstr_desc =
            Pstr_eval
              ({ pexp_desc = Pexp_constant (Pconst_integer (s, None)); _ }, _);
          _;
        };
      ] ->
      int_of_string s
  | _ ->
      Location.raise_errorf ~loc:attribute.attr_loc
        "[@@@@%s] expects an integer literal" attribute.attr_name.txt

let list_payload (attribute : attribute) =
  let invalid loc =
    Location.raise_errorf ~loc
      "[@@@@%s] expects a list literal, e.g. [@@@@%s [ a; b ]]"
      attribute.attr_name.txt attribute.attr_name.txt
  in
  let rec elements (expression : expression) =
    match expression.pexp_desc with
    | Pexp_construct ({ txt = Lident "[]"; _ }, None) -> []
    | Pexp_construct
        ( { txt = Lident "::"; _ },
          Some { pexp_desc = Pexp_tuple [ head; tail ]; _ } ) ->
        head :: elements tail
    | _ -> invalid expression.pexp_loc
  in
  match attribute.attr_payload with
  | PStr [ { pstr_desc = Pstr_eval (expression, _); _ } ] -> elements expression
  | _ -> invalid attribute.attr_loc

let segments path =
  List.filter (fun segment -> segment <> "") (String.split_on_char '/' path)

let ident ~loc path = pmod_ident ~loc { txt = Longident.parse path; loc }

let unsupported ~loc (type_ : core_type) =
  Location.raise_errorf ~loc
    "unsupported type %a; path and query parameters take int, int64, float, \
     bool, string or T.t with T : Kre_shared.Scalar.S; bodies and results also \
     take T.t with T : Kre_shared.Json.S and lists of those"
    Pprintast.core_type type_

let scalar ~loc (type_ : core_type) =
  {
    type_;
    module_ =
      (match type_.ptyp_desc with
      | Ptyp_constr ({ txt = Lident "int"; _ }, []) ->
          ident ~loc "Kre_shared.Scalar.Int"
      | Ptyp_constr ({ txt = Lident "int64"; _ }, []) ->
          ident ~loc "Kre_shared.Scalar.Int64"
      | Ptyp_constr ({ txt = Lident "float"; _ }, []) ->
          ident ~loc "Kre_shared.Scalar.Float"
      | Ptyp_constr ({ txt = Lident "bool"; _ }, []) ->
          ident ~loc "Kre_shared.Scalar.Bool"
      | Ptyp_constr ({ txt = Lident "string"; _ }, []) ->
          ident ~loc "Kre_shared.Scalar.String"
      | Ptyp_constr ({ txt = Ldot (path, "t"); loc }, []) ->
          pmod_ident ~loc { txt = path; loc }
      | _ -> unsupported ~loc type_);
  }

let rec json ~loc (type_ : core_type) =
  match type_.ptyp_desc with
  | Ptyp_constr ({ txt = Lident "list"; _ }, [ element ]) ->
      {
        type_;
        module_ =
          pmod_apply ~loc
            (ident ~loc "Kre_shared.Json.List")
            (json ~loc element).module_;
      }
  | Ptyp_constr ({ txt = Ldot (path, "t"); loc }, [ element ]) ->
      {
        type_;
        module_ =
          pmod_apply ~loc
            (pmod_ident ~loc { txt = Ldot (path, "Make"); loc })
            (json ~loc element).module_;
      }
  | _ -> scalar ~loc type_

let extraction (type_ : core_type) =
  List.find_map
    (fun (attribute : attribute) ->
      match (attribute.attr_name.txt, attribute.attr_payload) with
      | ("guard" | "from"), PStr [ { pstr_desc = Pstr_eval (guard, _); _ } ] ->
          Some guard
      | ("guard" | "from"), _ ->
          Location.raise_errorf ~loc:attribute.attr_loc
            "[@@%s] expects a guard expression of type 'a Kre.Guard.t"
            attribute.attr_name.txt
      | _ -> None)
    type_.ptyp_attributes

let transform structure =
  let verbs =
    [
      ("get", Get);
      ("post", Post);
      ("put", Put);
      ("patch", Patch);
      ("delete", Delete);
      ("head", Head);
      ("options", Options);
      ("all", All);
    ]
  in
  let verb_attribute (binding : value_binding) =
    List.find_map
      (fun (attribute : attribute) ->
        Option.map
          (fun verb -> (verb, attribute))
          (List.assoc_opt attribute.attr_name.txt verbs))
      binding.pvb_attributes
  in
  let controller_attribute (item : structure_item) =
    match item.pstr_desc with
    | Pstr_attribute ({ attr_name = { txt = "controller"; _ }; _ } as attribute)
      ->
        Some attribute
    | _ -> None
  in
  let positional_error loc =
    Location.raise_errorf ~loc
      "positional parameter must be (module M : S), (req : Dream.request), (x \
       : t [@from guard]) or (); use a labelled parameter for path, query and \
       body values"
  in
  let classify ~names ~host (param : function_param) =
    let loc = param.pparam_loc in
    let presence ~label ~(arg_label : arg_label) ~(default : expression option)
        (type_ : core_type) =
      match (type_.ptyp_desc, arg_label, default) with
      | _, Optional _, Some _ -> (Optional, type_)
      | Ptyp_constr ({ txt = Lident "option"; _ }, [ element ]), _, _ ->
          (Optional, element)
      | ( Ptyp_constr ({ txt = Lident "list"; _ }, [ element ]),
          (Labelled _ | Nolabel),
          _ ) ->
          (Repeated, element)
      | _, (Labelled _ | Nolabel), _ -> (Required, type_)
      | _ ->
          Location.raise_errorf ~loc
            "optional parameter %s needs a default or an option type: ?(%s : \
             int = 0) or ?(%s : int option)"
            label label label
    in
    let decorated ~label ~(arg_label : arg_label) ~(default : expression option)
        (type_ : core_type) =
      List.find_map
        (fun (attribute : attribute) ->
          let named () =
            match attribute.attr_payload with
            | PStr
                [
                  {
                    pstr_desc =
                      Pstr_eval
                        ( {
                            pexp_desc =
                              Pexp_constant (Pconst_string (name, _, _));
                            _;
                          },
                          _ );
                    _;
                  };
                ] ->
                Some name
            | PStr [] -> None
            | _ ->
                Location.raise_errorf ~loc:attribute.attr_loc
                  "[@@%s] takes nothing or a name: [@@%s \"x-request-id\"]"
                  attribute.attr_name.txt attribute.attr_name.txt
          in
          let required what =
            match named () with
            | Some name -> name
            | None ->
                Location.raise_errorf ~loc:attribute.attr_loc
                  "[@@%s] needs the %s name: [@@%s \"…\"]"
                  attribute.attr_name.txt what attribute.attr_name.txt
          in
          let extractor name = Extracted (evar ~loc ("Kre.Extract." ^ name)) in
          let located carrier what =
            let presence, element = presence ~label ~arg_label ~default type_ in
            Located
              {
                carrier;
                name = required what;
                presence;
                value = scalar ~loc element;
              }
          in
          match attribute.attr_name.txt with
          | "param" -> (
              let segment = required "path segment" in
              match List.find_opt (String.equal segment) names with
              | Some _ -> Some (Path { segment; value = scalar ~loc type_ })
              | None ->
                  Location.raise_errorf ~loc:attribute.attr_loc
                    "[@@param %S]: the path has no :%s segment" segment segment)
          | "query" -> (
              match named () with
              | Some name ->
                  let presence, element =
                    presence ~label ~arg_label ~default type_
                  in
                  Some (Query { name; presence; value = scalar ~loc element })
              | None -> Some (extractor "queries"))
          | "load" -> (
              let loader =
                match attribute.attr_payload with
                | PStr [ { pstr_desc = Pstr_eval (loader, _); _ } ] -> loader
                | _ ->
                    Location.raise_errorf ~loc:attribute.attr_loc
                      "[@@load] takes the function that finds the entity: \
                       [@@load Cats.find]"
              in
              match
                (type_.ptyp_desc, List.find_opt (String.equal label) names)
              with
              | Ptyp_constr ({ txt = Ldot (path, "t"); loc }, []), Some _ ->
                  Some
                    (Loaded
                       {
                         segment = label;
                         loader;
                         value =
                           {
                             type_ =
                               ptyp_constr ~loc
                                 { txt = Ldot (Ldot (path, "Id"), "t"); loc }
                                 [];
                             module_ =
                               pmod_ident ~loc { txt = Ldot (path, "Id"); loc };
                           };
                       })
              | Ptyp_constr ({ txt = Ldot (_, "t"); _ }, []), None ->
                  Location.raise_errorf ~loc:attribute.attr_loc
                    "[@@load] reads the path segment :%s; add it to the route, \
                     e.g. [@@@@get \":%s\"]"
                    label label
              | _ ->
                  Location.raise_errorf ~loc:attribute.attr_loc
                    "[@@load] loads an entity M.t whose id is M.Id.t")
          | "search" -> (
              match type_.ptyp_desc with
              | Ptyp_constr ({ txt = Ldot (path, "t"); loc }, []) ->
                  Some
                    (Searched
                       { type_; module_ = pmod_ident ~loc { txt = path; loc } })
              | _ ->
                  Location.raise_errorf ~loc:attribute.attr_loc
                    "[@@search] reads the query string into a record M.t with \
                     [@@@@deriving search, dto]")
          | "body" -> (
              match named () with
              | Some field ->
                  Some
                    (Extracted
                       [%expr
                         Kre.Extract.body_field
                           [%e pexp_pack ~loc (json ~loc type_).module_]
                           [%e estring ~loc field]])
              | None -> Some (Body (json ~loc type_)))
          | "header" -> Some (located Header "header")
          | "cookie" -> Some (located Cookie "cookie")
          | "signed_cookie" -> Some (located Signed_cookie "cookie")
          | "session" -> Some (located Session "session field")
          | "form" -> Some (located Form "form field")
          | "file" ->
              Some
                (Extracted
                   [%expr
                     Kre.Extract.file [%e estring ~loc (required "file field")]])
          | "files" ->
              Some
                (Extracted
                   [%expr
                     Kre.Extract.files [%e estring ~loc (required "file field")]])
          | ("headers" | "cookies" | "ip" | "host" | "req") as name ->
              Some (extractor name)
          | "wildcard" -> Some Wildcard
          | "host_param" -> (
              let name = required "host segment" in
              match host with
              | Some pattern ->
                  Some
                    (Extracted
                       [%expr
                         Kre.Extract.host_param
                           ~pattern:[%e estring ~loc pattern]
                           [%e estring ~loc name]])
              | None ->
                  Location.raise_errorf ~loc:attribute.attr_loc
                    "[@@host_param %S] reads the controller's host pattern; \
                     add [@@@@@@host \":%s.example.com\"]"
                    name name)
          | _ -> None)
        type_.ptyp_attributes
    in
    match param.pparam_desc with
    | Pparam_newtype _ ->
        Location.raise_errorf ~loc
          "handlers cannot take (type a) parameters; move them into a helper"
    | Pparam_val (Nolabel, _, pattern) ->
        let source =
          match pattern.ppat_desc with
          | Ppat_constraint
              ( { ppat_desc = Ppat_unpack { txt = Some name; _ }; _ },
                ({ ptyp_desc = Ptyp_package _; _ } as package) ) ->
              Dependency { name; pattern; package }
          | Ppat_construct ({ txt = Lident "()"; _ }, None) -> Unit
          | Ppat_constraint (_, type_) -> (
              match
                ( decorated ~label:"positional" ~arg_label:Nolabel ~default:None
                    type_,
                  extraction type_,
                  type_.ptyp_desc )
              with
              | Some decorated, _, _ -> decorated
              | None, Some guard, _ -> Extracted guard
              | ( None,
                  None,
                  Ptyp_constr ({ txt = Ldot (Lident "Dream", "request"); _ }, [])
                ) ->
                  Request
              | None, None, _ -> positional_error loc)
          | _ -> positional_error loc
        in
        { label = Nolabel; source; loc }
    | Pparam_val
        (((Labelled label | Optional label) as arg_label), default, pattern) ->
        let annotated () =
          match pattern.ppat_desc with
          | Ppat_constraint (_, type_) -> type_
          | _ ->
              Location.raise_errorf ~loc
                "parameter %s needs a type annotation: ~(%s : int)" label label
        in
        let source =
          match
            Option.bind
              (match pattern.ppat_desc with
              | Ppat_constraint (_, type_) -> Some type_
              | _ -> None)
              (decorated ~label ~arg_label ~default)
          with
          | Some decorated -> decorated
          | None -> (
              match
                ( List.find_opt (String.equal label) names,
                  label,
                  Option.bind
                    (match pattern.ppat_desc with
                    | Ppat_constraint (_, type_) -> Some type_
                    | _ -> None)
                    extraction,
                  arg_label )
              with
              | Some _, _, _, Optional _ ->
                  Location.raise_errorf ~loc
                    "path parameter %s cannot be optional; use ~(%s : …)" label
                    label
              | Some _, _, _, _ ->
                  Path { segment = label; value = scalar ~loc (annotated ()) }
              | None, "body", None, _ -> Body (json ~loc (annotated ()))
              | None, _, Some guard, _ -> Extracted guard
              | None, _, None, _ ->
                  let presence, element =
                    presence ~label ~arg_label ~default (annotated ())
                  in
                  Query { name = label; presence; value = scalar ~loc element })
        in
        { label = arg_label; source; loc }
  in
  let returns ~name (type_ : core_type) =
    let loc = type_.ptyp_loc in
    match type_.ptyp_desc with
    | Ptyp_constr ({ txt = Ldot (Lident "Lwt", "t"); _ }, [ inner ]) ->
        let outcome, payload =
          match inner.ptyp_desc with
          | Ptyp_constr ({ txt = Lident "result"; _ }, [ ok; _ ]) ->
              (Fallible, ok)
          | _ -> (Plain, inner)
        in
        let shape =
          match payload.ptyp_desc with
          | Ptyp_constr ({ txt = Lident "unit"; _ }, []) -> Empty
          | Ptyp_constr ({ txt = Lident "string"; _ }, []) -> Text
          | Ptyp_constr ({ txt = Ldot (Lident "Dream", "response"); _ }, []) ->
              Raw
          | Ptyp_constr ({ txt = Lident "option"; _ }, [ found ]) ->
              Found (json ~loc found)
          | Ptyp_constr ({ txt = Ldot (Lident "Lwt_stream", "t"); _ }, [ event ])
            ->
              Stream (json ~loc event)
          | _ -> Json (json ~loc payload)
        in
        (shape, outcome)
    | _ ->
        Location.raise_errorf ~loc
          "handler %s must return a promise: t Lwt.t or (t, Kre.Error.t) \
           result Lwt.t, where t is unit, string, Dream.response, T.t, T.t \
           list or T.t option"
          name
  in
  match structure with
  | [] -> []
  | first :: rest -> (
      match controller_attribute first with
      | None ->
          Option.iter
            (fun (attribute : attribute) ->
              Location.raise_errorf ~loc:attribute.attr_loc
                "[@@@@@@controller] must be the first item of the file")
            (List.find_map controller_attribute rest);
          Option.fold ~none:structure
            ~some:(fun ((_ : verb), (attribute : attribute)) ->
              Location.raise_errorf ~loc:attribute.attr_loc
                "[@@@@%s] outside a controller; add [@@@@@@controller \
                 \"prefix\"] as the first item of the file"
                attribute.attr_name.txt)
            (List.find_map
               (fun (item : structure_item) ->
                 match item.pstr_desc with
                 | Pstr_value (_, bindings) ->
                     List.find_map verb_attribute bindings
                 | _ -> None)
               structure)
      | Some controller ->
          let loc = controller.attr_loc in
          let floating name =
            List.filter_map
              (fun (item : structure_item) ->
                match item.pstr_desc with
                | Pstr_attribute attribute when attribute.attr_name.txt = name
                  ->
                    Some attribute
                | _ -> None)
              rest
          in
          Option.iter
            (fun (attribute : attribute) ->
              Location.raise_errorf ~loc:attribute.attr_loc
                "second [@@@@@@controller]; a file is one controller")
            (List.nth_opt (floating "controller") 0);
          let prefix = segments (string_payload controller) in
          let version =
            Option.map int_payload (List.nth_opt (floating "version") 0)
          in
          let host =
            Option.map string_payload (List.nth_opt (floating "host") 0)
          in
          let controller_middleware =
            List.concat_map list_payload (floating "use")
          in
          let controller_interceptors =
            List.concat_map list_payload (floating "intercept")
          in
          let controller_guards =
            List.concat_map list_payload (floating "guards")
          in
          let attribute_of (binding : value_binding) name =
            List.find_opt
              (fun (attribute : attribute) -> attribute.attr_name.txt = name)
              binding.pvb_attributes
          in
          let handler (binding : value_binding) (verb, (attribute : attribute))
              =
            let name =
              match binding.pvb_pat.ppat_desc with
              | Ppat_var { txt; _ } -> txt
              | _ ->
                  Location.raise_errorf ~loc:binding.pvb_pat.ppat_loc
                    "[@@@@%s] needs a plain name: let find_one … = …"
                    attribute.attr_name.txt
            in
            let params, return_type =
              match binding.pvb_expr.pexp_desc with
              | Pexp_function
                  (params, Some (Pconstraint type_), Pfunction_body _) ->
                  (params, type_)
              | Pexp_function (_, None, _) ->
                  Location.raise_errorf ~loc:binding.pvb_expr.pexp_loc
                    "handler %s: missing return type annotation; add one \
                     before =, e.g. : Cat.t Lwt.t"
                    name
              | _ ->
                  Location.raise_errorf ~loc:binding.pvb_expr.pexp_loc
                    "handler %s must be a function with its parameters on the \
                     let: let %s (…) () : t Lwt.t = …"
                    name name
            in
            let raw_segments =
              Option.fold ~none:[]
                ~some:(fun version -> [ "v" ^ string_of_int version ])
                (Option.fold ~none:version
                   ~some:(fun attribute -> Some (int_payload attribute))
                   (attribute_of binding "version"))
              @ prefix
              @ segments (string_payload attribute)
            in
            let param_name segment =
              match String.split_on_char ':' segment with
              | [ ""; name ] -> Some name
              | _ -> None
            in
            let arguments =
              List.map
                (classify ~host
                   ~names:(List.filter_map param_name raw_segments))
                params
            in
            (match
               List.filter_map
                 (fun argument ->
                   match argument.source with
                   | Body _ -> Some argument.loc
                   | _ -> None)
                 arguments
             with
            | _ :: second :: _ ->
                Location.raise_errorf ~loc:second
                  "handler %s has two body parameters; keep one ~(body : T.t)"
                  name
            | _ -> ());
            let shape, outcome = returns ~name return_type in
            let shape =
              Option.fold ~none:shape
                ~some:(fun (attribute : attribute) ->
                  match shape with
                  | Empty -> Moved (string_payload attribute)
                  | Text | Raw | Json _ | Found _ | Moved _ | Stream _ ->
                      Location.raise_errorf ~loc:attribute.attr_loc
                        "[@@@@redirect] needs a handler returning unit Lwt.t")
                (attribute_of binding "redirect")
            in
            (match
               ( shape,
                 attribute_of binding "sse",
                 attribute_of binding "timeout" )
             with
            | Stream _, Some _, None
            | (Empty | Text | Raw | Json _ | Found _ | Moved _), None, _ ->
                ()
            | Stream _, None, _ ->
                Location.raise_errorf ~loc:return_type.ptyp_loc
                  "handler %s returns a stream; add [@@@@sse] to send it as \
                   server-sent events"
                  name
            | Stream _, Some _, Some attribute ->
                Location.raise_errorf ~loc:attribute.attr_loc
                  "[@@@@timeout] does not apply to [@@@@sse]: an event stream \
                   stays open"
            | ( (Empty | Text | Raw | Json _ | Found _ | Moved _),
                Some attribute,
                _ ) ->
                Location.raise_errorf ~loc:attribute.attr_loc
                  "[@@@@sse] needs a handler returning T.t Lwt_stream.t Lwt.t");
            let live =
              Option.fold ~none:[]
                ~some:(fun (attribute : attribute) ->
                  match verb with
                  | Get ->
                      List.map
                        (fun (table : expression) ->
                          match table.pexp_desc with
                          | Pexp_constant (Pconst_string (table, _, _)) -> table
                          | _ ->
                              Location.raise_errorf ~loc:table.pexp_loc
                                "[@@@@live] lists table names as strings: \
                                 [@@@@live [ \"cats\" ]]")
                        (list_payload attribute)
                  | Post | Put | Patch | Delete | Head | Options | All ->
                      Location.raise_errorf ~loc:attribute.attr_loc
                        "[@@@@live] reloads pages that GET data; %s is not a \
                         GET"
                        name)
                (attribute_of binding "live")
            in
            let closure kind =
              Option.map
                (fun (attribute : attribute) ->
                  let check =
                    match attribute.attr_payload with
                    | PStr [ { pstr_desc = Pstr_eval (check, _); _ } ] -> check
                    | _ ->
                        Location.raise_errorf ~loc:attribute.attr_loc
                          "[@@@@%s] expects a function, e.g. [@@@@%s fun ~user \
                           ~id -> …]"
                          kind kind
                  in
                  let labels =
                    match check.pexp_desc with
                    | Pexp_function (params, _, _) ->
                        List.map
                          (fun (param : function_param) ->
                            match param.pparam_desc with
                            | Pparam_val (Labelled label, None, _) -> label
                            | _ ->
                                Location.raise_errorf ~loc:param.pparam_loc
                                  "[@@@@%s] takes only labelled arguments \
                                   named like the handler's"
                                  kind)
                          params
                    | _ ->
                        Location.raise_errorf ~loc:check.pexp_loc
                          "[@@@@%s] expects a function, e.g. [@@@@%s fun ~user \
                           ~id -> …]"
                          kind kind
                  in
                  pexp_apply ~loc check
                    (List.map
                       (fun label ->
                         match
                           List.find_map
                             (fun argument ->
                               match (argument.label, argument.source) with
                               | ( (Labelled known | Optional known),
                                   ( Path _ | Query _ | Body _ | Searched _
                                   | Loaded _ | Extracted _ | Located _ ) )
                                 when String.equal known label ->
                                   Some argument
                               | _ -> None)
                             arguments
                         with
                         | Some { source = Path { segment; _ }; _ } ->
                             (Labelled label, evar ~loc ("__kre_arg_" ^ segment))
                         | Some _ ->
                             (Labelled label, evar ~loc ("__kre_arg_" ^ label))
                         | None ->
                             Location.raise_errorf ~loc:check.pexp_loc
                               "[@@@@%s] uses ~%s, which %s does not take" kind
                               label name)
                       labels))
                (attribute_of binding kind)
            in
            {
              name;
              verb;
              segments =
                List.map
                  (fun segment ->
                    match segment with
                    | "*" -> Rest
                    | segment ->
                        Option.fold ~none:(Literal segment)
                          ~some:(fun name ->
                            Param
                              {
                                name;
                                value =
                                  (match
                                     List.find_map
                                       (fun argument ->
                                         match argument.source with
                                         | Path { segment; value }
                                         | Loaded { segment; value; _ }
                                           when String.equal segment name ->
                                             Some value
                                         | _ -> None)
                                       arguments
                                   with
                                  | Some value -> value
                                  | None ->
                                      Location.raise_errorf
                                        ~loc:attribute.attr_loc
                                        "path segment :%s has no parameter; \
                                         add ~(%s : int) to the handler"
                                        name name);
                              })
                          (param_name segment))
                  raw_segments;
              status =
                Option.fold
                  ~none:
                    (match shape with
                    | Empty -> 204
                    | Moved _ -> 302
                    | Text | Raw | Json _ | Found _ | Stream _ -> 200)
                  ~some:(fun attribute ->
                    match int_payload attribute with
                    | status when status >= 100 && status <= 599 -> status
                    | status ->
                        Location.raise_errorf ~loc:attribute.attr_loc
                          "[@@@@status %d] is not an HTTP status; use 100–599"
                          status)
                  (attribute_of binding "status");
              middleware =
                (Option.fold ~none:[]
                   ~some:(fun (attribute : attribute) ->
                     match verb with
                     | Get -> [ [%expr Kre.Etag.middleware] ]
                     | Post | Put | Patch | Delete | Head | Options | All ->
                         Location.raise_errorf ~loc:attribute.attr_loc
                           "[@@@@etag] answers 304 to a repeated GET; %s is \
                            not a GET"
                           name)
                   (attribute_of binding "etag")
                @ Option.fold ~none:[] ~some:list_payload
                    (attribute_of binding "use")
                @ Option.fold ~none:[]
                    ~some:(fun (attribute : attribute) ->
                      match (verb, attribute.attr_payload) with
                      | ( Get,
                          PStr
                            [
                              {
                                pstr_desc =
                                  Pstr_eval
                                    ( ({
                                         pexp_desc =
                                           Pexp_constant (Pconst_float _);
                                         _;
                                       } as ttl),
                                      _ );
                                _;
                              };
                            ] ) ->
                          [ [%expr Kre.Cache.response ~ttl:[%e ttl] ()] ]
                      | Get, _ ->
                          Location.raise_errorf ~loc:attribute.attr_loc
                            "[@@@@cache] takes seconds as a float: [@@@@cache \
                             60.0]"
                      | (Post | Put | Patch | Delete | Head | Options | All), _
                        ->
                          Location.raise_errorf ~loc:attribute.attr_loc
                            "[@@@@cache] caches GET responses; %s is not a GET"
                            name)
                    (attribute_of binding "cache")
                @
                match live with
                | [] -> []
                | tables ->
                    [
                      [%expr
                        Kre.Live.audit
                          [%e
                            elist ~loc
                              (List.map
                                 (fun table -> estring ~loc table)
                                 tables)]];
                    ]);
              live;
              guards =
                controller_guards
                @ Option.fold ~none:[] ~some:list_payload
                    (attribute_of binding "guards")
                @ Option.fold ~none:[]
                    ~some:(fun (attribute : attribute) ->
                      match attribute.attr_payload with
                      | PStr [ { pstr_desc = Pstr_eval (guard, _); _ } ] ->
                          [ [%expr Kre.Guard.map ignore [%e guard]] ]
                      | _ ->
                          Location.raise_errorf ~loc:attribute.attr_loc
                            "[@@@@role] takes a guard whose value the handler \
                             does not need: [@@@@role Auth.admin]")
                    (attribute_of binding "role")
                @ Option.fold ~none:[]
                    ~some:(fun (attribute : attribute) ->
                      match attribute.attr_payload with
                      | PStr [ { pstr_desc = Pstr_eval (secret, _); _ } ] ->
                          [ [%expr Kre.Signed.guard ~secret:[%e secret] ()] ]
                      | _ ->
                          Location.raise_errorf ~loc:attribute.attr_loc
                            "[@@@@signed] takes the signing secret: \
                             [@@@@signed Settings.config.signing_key]")
                    (attribute_of binding "signed");
              arguments;
              shape;
              outcome;
              summary =
                Option.map string_payload (attribute_of binding "summary");
              description =
                Option.map string_payload (attribute_of binding "description");
              error_handler =
                Option.map
                  (fun (attribute : attribute) ->
                    match attribute.attr_payload with
                    | PStr [ { pstr_desc = Pstr_eval (handler, _); _ } ] ->
                        handler
                    | _ ->
                        Location.raise_errorf ~loc:attribute.attr_loc
                          "[@@@@error_handler] expects a Kre.Error.handler")
                  (attribute_of binding "error_handler");
              interceptors =
                controller_interceptors
                @ Option.fold ~none:[] ~some:list_payload
                    (attribute_of binding "intercept");
              headers =
                List.filter_map
                  (fun (attribute : attribute) ->
                    match (attribute.attr_name.txt, attribute.attr_payload) with
                    | ( "header",
                        PStr [ { pstr_desc = Pstr_eval (header, _); _ } ] ) ->
                        Some header
                    | "header", _ ->
                        Location.raise_errorf ~loc:attribute.attr_loc
                          "[@@@@header] expects a pair: [@@@@header \
                           (\"Cache-Control\", \"no-store\")]"
                    | _ -> None)
                  binding.pvb_attributes;
              authorize = closure "authorize";
              check = closure "check";
              transaction =
                (match
                   ( attribute_of binding "transactional",
                     List.find_map
                       (fun argument ->
                         match argument.source with
                         | Extracted
                             {
                               pexp_desc =
                                 Pexp_ident { txt = Ldot (db, "tx"); _ };
                               _;
                             } ->
                             Some (db, argument.loc)
                         | _ -> None)
                       arguments,
                     List.filter_map
                       (fun argument ->
                         match argument.source with
                         | Dependency
                             {
                               name;
                               package =
                                 {
                                   ptyp_desc =
                                     Ptyp_package
                                       ( {
                                           txt =
                                             Ldot
                                               (Ldot (Lident "Kre", "Db"), "S");
                                           _;
                                         },
                                         _ );
                                   _;
                                 };
                               _;
                             } ->
                             Some name
                         | _ -> None)
                       arguments )
                 with
                | Some _, Some (db, _), _ -> Some db
                | Some _, None, [ db ] -> Some (Lident db)
                | None, None, _ -> None
                | Some attribute, None, [] ->
                    Location.raise_errorf ~loc:attribute.attr_loc
                      "[@@@@transactional] runs %s in a transaction of a \
                       Kre.Db.S dependency; add (module Db : Kre.Db.S with \
                       type conn = …)"
                      name
                | Some attribute, None, (first :: _ :: _ as databases) ->
                    Location.raise_errorf ~loc:attribute.attr_loc
                      "[@@@@transactional] sees several Kre.Db.S dependencies \
                       (%s); pick one with ~(conn : … [@@from %s.tx])"
                      (String.concat ", " databases)
                      first
                | None, Some (db, loc), _ ->
                    Location.raise_errorf ~loc
                      "[@@from %s.tx] reads the open transaction; add \
                       [@@@@transactional] to %s"
                      (Longident.name db) name);
              timeout =
                Option.map
                  (fun (attribute : attribute) ->
                    match attribute.attr_payload with
                    | PStr
                        [
                          {
                            pstr_desc =
                              Pstr_eval
                                ( ({
                                     pexp_desc = Pexp_constant (Pconst_float _);
                                     _;
                                   } as seconds),
                                  _ );
                            _;
                          };
                        ] ->
                        seconds
                    | _ ->
                        Location.raise_errorf ~loc:attribute.attr_loc
                          "[@@@@timeout] expects seconds as a float: \
                           [@@@@timeout 5.0]")
                  (attribute_of binding "timeout");
            }
          in
          let handler_attributes =
            [
              "status";
              "use";
              "guards";
              "role";
              "signed";
              "check";
              "header";
              "redirect";
              "timeout";
              "transactional";
              "authorize";
              "sse";
              "intercept";
              "cache";
              "version";
              "error_handler";
              "summary";
              "description";
              "live";
              "etag";
            ]
            @ List.map fst verbs
          in
          let items, handlers =
            List.fold_left
              (fun (items, handlers) (item : structure_item) ->
                match item.pstr_desc with
                | Pstr_attribute attribute
                  when List.mem attribute.attr_name.txt
                         [
                           "controller";
                           "use";
                           "guards";
                           "version";
                           "error_handler";
                           "intercept";
                           "host";
                         ] ->
                    (items, handlers)
                | Pstr_value (flag, bindings) -> (
                    match
                      (List.filter_map verb_attribute bindings, flag, bindings)
                    with
                    | [], _, _ -> (item :: items, handlers)
                    | (_, attribute) :: _, Recursive, _ ->
                        Location.raise_errorf ~loc:attribute.attr_loc
                          "[@@@@%s] on let rec: handlers cannot be recursive; \
                           move the recursion into a helper"
                          attribute.attr_name.txt
                    | [ found ], Nonrecursive, [ binding ] ->
                        ( {
                            item with
                            pstr_desc =
                              Pstr_value
                                ( flag,
                                  [
                                    {
                                      binding with
                                      pvb_attributes =
                                        List.filter
                                          (fun (attribute : attribute) ->
                                            not
                                              (List.mem attribute.attr_name.txt
                                                 handler_attributes))
                                          binding.pvb_attributes;
                                    };
                                  ] );
                          }
                          :: items,
                          handler binding found :: handlers )
                    | (_, attribute) :: _, Nonrecursive, _ ->
                        Location.raise_errorf ~loc:attribute.attr_loc
                          "[@@@@%s] on let … and …: declare each handler with \
                           its own let"
                          attribute.attr_name.txt)
                | _ -> (item :: items, handlers))
              ([], []) rest
          in
          let handlers = List.rev handlers in
          let print printer value = Format.asprintf "%a" printer value in
          let dependencies =
            List.fold_left
              (fun dependencies argument ->
                match argument.source with
                | Dependency { name; pattern; package } -> (
                    match List.assoc_opt name dependencies with
                    | None -> dependencies @ [ (name, (pattern, package)) ]
                    | Some (_, known)
                      when print Pprintast.core_type known
                           = print Pprintast.core_type package ->
                        dependencies
                    | Some (_, known) ->
                        let signature (package : core_type) =
                          match package.ptyp_desc with
                          | Ptyp_package ({ txt; _ }, _) -> Longident.name txt
                          | _ -> print Pprintast.core_type package
                        in
                        Location.raise_errorf ~loc:argument.loc
                          "dependency %s has two signatures in this \
                           controller, %s and %s; rename one of them"
                          name (signature known) (signature package))
                | _ -> dependencies)
              []
              (List.concat_map (fun handler -> handler.arguments) handlers)
          in
          let methods handler =
            match handler.verb with
            | Get -> [ "GET" ]
            | Post -> [ "POST" ]
            | Put -> [ "PUT" ]
            | Patch -> [ "PATCH" ]
            | Delete -> [ "DELETE" ]
            | Head -> [ "HEAD" ]
            | Options -> [ "OPTIONS" ]
            | All ->
                [ "GET"; "POST"; "PUT"; "PATCH"; "DELETE"; "HEAD"; "OPTIONS" ]
          in
          let verb_tag method_ = pexp_variant ~loc method_ None in
          let variable label = "__kre_arg_" ^ label in
          let bound index argument =
            match argument.label with
            | Labelled label | Optional label -> variable label
            | Nolabel -> variable (string_of_int index)
          in
          let path_expression handler =
            let ending =
              match List.rev handler.segments with
              | Rest :: _ -> [%expr Routes.wildcard]
              | _ -> [%expr Routes.nil]
            in
            match
              List.filter_map
                (function
                  | Literal segment ->
                      Some [%expr Routes.s [%e estring ~loc segment]]
                  | Param { name; value } ->
                      Some
                        [%expr
                          Kre.Route.segment
                            [%e pexp_pack ~loc value.module_]
                            [%e estring ~loc (":" ^ name)]]
                  | Rest -> None)
                handler.segments
            with
            | [] -> ending
            | first :: rest ->
                [%expr
                  Routes.( /? )
                    [%e
                      List.fold_left
                        (fun joined next ->
                          [%expr Routes.( / ) [%e joined] [%e next]])
                        first rest]
                    [%e ending]]
          in
          let route handler method_ =
            let extractions =
              List.concat
                (List.mapi
                   (fun index argument ->
                     match argument.source with
                     | Query { name; presence; value } ->
                         [
                           ( bound index argument,
                             [%expr
                               Kre.Route.query
                                 [%e pexp_pack ~loc value.module_]
                                 [%e
                                   match presence with
                                   | Required ->
                                       [%expr Kre_shared.Presence.Required]
                                   | Optional ->
                                       [%expr Kre_shared.Presence.Optional]
                                   | Repeated ->
                                       [%expr Kre_shared.Presence.Repeated]]
                                 [%e estring ~loc name] __kre_request] );
                         ]
                     | Body value ->
                         [
                           ( bound index argument,
                             [%expr
                               Kre.Route.body
                                 [%e pexp_pack ~loc value.module_]
                                 __kre_request] );
                         ]
                     | Loaded { segment; loader; _ } ->
                         [
                           ( bound index argument,
                             [%expr
                               Kre.Route.load ~what:[%e estring ~loc segment]
                                 [%e loader]
                                 [%e evar ~loc (variable segment)]] );
                         ]
                     | Searched value ->
                         [
                           ( bound index argument,
                             [%expr
                               Kre.Extract.search
                                 (let module M = [%m value.module_] in
                                  M.codec)
                                 __kre_request] );
                         ]
                     | Extracted guard ->
                         [
                           ( bound index argument,
                             [%expr [%e guard] __kre_request] );
                         ]
                     | Located { carrier; name; presence; value } ->
                         [
                           ( bound index argument,
                             [%expr
                               [%e
                                 evar ~loc
                                   (match carrier with
                                   | Header -> "Kre.Extract.header"
                                   | Cookie -> "Kre.Extract.cookie"
                                   | Signed_cookie ->
                                       "Kre.Extract.signed_cookie"
                                   | Session -> "Kre.Extract.session"
                                   | Form -> "Kre.Extract.form")]
                                 [%e pexp_pack ~loc value.module_]
                                 [%e
                                   match presence with
                                   | Required ->
                                       [%expr Kre_shared.Presence.Required]
                                   | Optional ->
                                       [%expr Kre_shared.Presence.Optional]
                                   | Repeated ->
                                       [%expr Kre_shared.Presence.Repeated]]
                                 [%e estring ~loc name] __kre_request] );
                         ]
                     | Dependency _ | Path _ | Wildcard | Request | Unit -> [])
                   handler.arguments)
            in
            let call =
              pexp_apply ~loc (evar ~loc handler.name)
                (List.mapi
                   (fun index argument ->
                     ( argument.label,
                       match argument.source with
                       | Dependency { name; _ } ->
                           pexp_pack ~loc (ident ~loc name)
                       | Request -> [%expr __kre_request]
                       | Unit -> [%expr ()]
                       | Path { segment; _ } -> evar ~loc (variable segment)
                       | Wildcard -> [%expr Kre.Route.rest __kre_rest]
                       | Query _ | Body _ | Searched _ | Loaded _ | Extracted _
                       | Located _ ->
                           evar ~loc (bound index argument) ))
                   handler.arguments)
            in
            let result =
              match handler.outcome with
              | Plain -> [%expr Kre.Route.ok [%e call]]
              | Fallible -> call
            in
            let steps =
              List.map
                (fun (name, expression) -> (pvar ~loc name, expression))
                extractions
              @ Option.fold ~none:[]
                  ~some:(fun check -> [ ([%pat? ()], check) ])
                  handler.authorize
              @ Option.fold ~none:[]
                  ~some:(fun check ->
                    [ ([%pat? ()], [%expr Kre.Route.validated [%e check]]) ])
                  handler.check
            in
            let body =
              match steps with
              | [] -> result
              | _ ->
                  [%expr
                    let open Kre.Route.Syntax in
                    [%e
                      List.fold_right
                        (fun (pattern, expression) rest ->
                          pexp_letop ~loc
                            (letop
                               ~let_:
                                 (binding_op ~loc ~op:{ txt = "let*"; loc }
                                    ~pat:pattern ~exp:expression)
                               ~ands:[] ~body:rest))
                        steps result]]
            in
            let callee, form, timeout =
              match handler.shape with
              | Stream value ->
                  ([%expr Kre.Route.events], pexp_pack ~loc value.module_, [])
              | (Empty | Text | Raw | Json _ | Found _ | Moved _) as shape ->
                  ( [%expr Kre.Route.handle],
                    (match shape with
                    | Empty -> [%expr Kre.Route.Unit]
                    | Text -> [%expr Kre.Route.Text]
                    | Raw -> [%expr Kre.Route.Raw]
                    | Json value ->
                        [%expr Kre.Route.Json [%e pexp_pack ~loc value.module_]]
                    | Found value ->
                        [%expr
                          Kre.Route.Found [%e pexp_pack ~loc value.module_]]
                    | Moved location ->
                        [%expr Kre.Route.Redirect [%e estring ~loc location]]
                    | Stream value -> pexp_pack ~loc value.module_),
                    Option.fold ~none:[]
                      ~some:(fun timeout -> [ (Labelled "timeout", timeout) ])
                      handler.timeout )
            in
            let handle =
              pexp_apply ~loc callee
                ([
                   ( Labelled "status",
                     [%expr Dream.int_to_status [%e eint ~loc handler.status]]
                   );
                 ]
                @ (match handler.guards with
                  | [] -> []
                  | guards -> [ (Labelled "guards", elist ~loc guards) ])
                @ (match handler.headers with
                  | [] -> []
                  | headers -> [ (Labelled "headers", elist ~loc headers) ])
                @ (match handler.interceptors with
                  | [] -> []
                  | interceptors ->
                      [ (Labelled "interceptors", elist ~loc interceptors) ])
                @ timeout
                @ [
                    (Nolabel, form);
                    ( Nolabel,
                      [%expr
                        fun __kre_request ->
                          [%e
                            Option.fold ~none:body
                              ~some:(fun db ->
                                [%expr
                                  [%e
                                    pexp_ident ~loc
                                      { txt = Ldot (db, "within"); loc }]
                                    __kre_request (fun () -> [%e body])])
                              handler.transaction]] );
                  ])
            in
            let target =
              List.fold_right
                (fun segment target ->
                  match segment with
                  | Literal _ -> target
                  | Param { name; _ } ->
                      [%expr fun [%p pvar ~loc (variable name)] -> [%e target]]
                  | Rest -> [%expr fun __kre_rest -> [%e target]])
                handler.segments handle
            in
            pexp_apply ~loc [%expr Kre.Route.v]
              (Option.fold ~none:[]
                 ~some:(fun handler -> [ (Labelled "error_handler", handler) ])
                 handler.error_handler
              @ (match handler.middleware with
                | [] -> []
                | middleware ->
                    [ (Labelled "middleware", elist ~loc middleware) ])
              @ [
                  (Nolabel, verb_tag method_);
                  ( Nolabel,
                    [%expr
                      Routes.( @--> )
                        ([%e evar ~loc ("Paths." ^ handler.name)] ())
                        [%e target]] );
                ])
          in
          let spec_value value =
            [%expr
              {
                Kre.Spec.type_ =
                  [%e estring ~loc (print Pprintast.core_type value.type_)];
                module_ =
                  [%e
                    estring ~loc
                      (let rec name (module_ : module_expr) =
                         match module_.pmod_desc with
                         | Pmod_ident { txt; _ } -> Longident.name txt
                         | Pmod_apply (functor_, argument) ->
                             name functor_ ^ " (" ^ name argument ^ ")"
                         | _ -> print Pprintast.module_expr module_
                       in
                       name value.module_)];
                schema =
                  (let module M = [%m value.module_] in
                   M.t_jsonschema);
              }]
          in
          let spec_route handler method_ =
            [%expr
              {
                Kre.Spec.verb = [%e verb_tag method_];
                path =
                  [%e
                    estring ~loc
                      ("/"
                      ^ String.concat "/"
                          (List.map
                             (function
                               | Literal segment -> segment
                               | Param { name; _ } -> ":" ^ name
                               | Rest -> "*")
                             handler.segments))];
                name = [%e estring ~loc handler.name];
                params =
                  [%e
                    let presence_expression = function
                      | Required -> [%expr Kre.Spec.Required]
                      | Optional -> [%expr Kre.Spec.Optional]
                      | Repeated -> [%expr Kre.Spec.Repeated]
                    in
                    elist ~loc
                      (List.filter_map
                         (fun argument ->
                           Option.map
                             (fun (name, location, value) ->
                               [%expr
                                 {
                                   Kre.Spec.name = [%e estring ~loc name];
                                   label =
                                     [%e
                                       estring ~loc
                                         (match argument.label with
                                         | Labelled label | Optional label ->
                                             label
                                         | Nolabel -> name)];
                                   location = [%e location];
                                   value = [%e spec_value value];
                                 }])
                             (match argument.source with
                             | Path { segment; value }
                             | Loaded { segment; value; _ } ->
                                 Some (segment, [%expr Kre.Spec.Path], value)
                             | Query { name; presence; value } ->
                                 Some
                                   ( name,
                                     [%expr
                                       Kre.Spec.Query
                                         [%e presence_expression presence]],
                                     value )
                             | Located
                                 { carrier = Header; name; presence; value } ->
                                 Some
                                   ( name,
                                     [%expr
                                       Kre.Spec.Header
                                         [%e presence_expression presence]],
                                     value )
                             | Located
                                 {
                                   carrier = Cookie | Signed_cookie;
                                   name;
                                   presence;
                                   value;
                                 } ->
                                 Some
                                   ( name,
                                     [%expr
                                       Kre.Spec.Cookie
                                         [%e presence_expression presence]],
                                     value )
                             | Searched value ->
                                 Some
                                   ( (match argument.label with
                                     | Labelled label | Optional label -> label
                                     | Nolabel -> "search"),
                                     [%expr Kre.Spec.Search],
                                     value )
                             | Located { carrier = Session | Form; _ }
                             | Dependency _ | Body _ | Extracted _ | Wildcard
                             | Request | Unit ->
                                 None))
                         handler.arguments)];
                body =
                  [%e
                    Option.fold ~none:[%expr None]
                      ~some:(fun value -> [%expr Some [%e spec_value value]])
                      (List.find_map
                         (fun argument ->
                           match argument.source with
                           | Body value -> Some value
                           | _ -> None)
                         handler.arguments)];
                returns =
                  [%e
                    match handler.shape with
                    | Empty | Moved _ -> [%expr Kre.Spec.Unit]
                    | Text -> [%expr Kre.Spec.Text]
                    | Raw -> [%expr Kre.Spec.Raw]
                    | Json value | Found value ->
                        [%expr Kre.Spec.Json [%e spec_value value]]
                    | Stream value ->
                        [%expr Kre.Spec.Events [%e spec_value value]]];
                status = Dream.int_to_status [%e eint ~loc handler.status];
                summary =
                  [%e
                    Option.fold ~none:[%expr None]
                      ~some:(fun summary ->
                        [%expr Some [%e estring ~loc summary]])
                      handler.summary];
                description =
                  [%e
                    Option.fold ~none:[%expr None]
                      ~some:(fun description ->
                        [%expr Some [%e estring ~loc description]])
                      handler.description];
                live =
                  [%e
                    elist ~loc
                      (List.map (fun table -> estring ~loc table) handler.live)];
                guards =
                  [%e
                    elist ~loc
                      (List.map
                         (fun guard ->
                           estring ~loc (print Pprintast.expression guard))
                         handler.guards)];
              }]
          in
          let paths =
            pstr_module ~loc
              (module_binding ~loc
                 ~name:{ txt = Some "Paths"; loc }
                 ~expr:
                   (pmod_structure ~loc
                      (List.map
                         (fun handler ->
                           [%stri
                             let [%p pvar ~loc handler.name] =
                              fun () -> [%e path_expression handler]])
                         handlers)))
          in
          let spec =
            [%stri
              let spec : Kre.Spec.t =
                {
                  Kre.Spec.prefix =
                    [%e estring ~loc ("/" ^ String.concat "/" prefix)];
                  version =
                    [%e
                      Option.fold ~none:[%expr None]
                        ~some:(fun version ->
                          [%expr Some [%e eint ~loc version]])
                        version];
                  routes =
                    [%e
                      elist ~loc
                        (List.concat_map
                           (fun handler ->
                             List.map (spec_route handler) (methods handler))
                           handlers)];
                }]
          in
          let controller_value =
            pexp_apply ~loc [%expr Kre.Controller.v]
              ((match controller_middleware with
                 | [] -> []
                 | middleware ->
                     [ (Labelled "middleware", elist ~loc middleware) ])
              @ Option.fold ~none:[]
                  ~some:(fun (attribute : attribute) ->
                    match attribute.attr_payload with
                    | PStr [ { pstr_desc = Pstr_eval (handler, _); _ } ] ->
                        [ (Labelled "error_handler", handler) ]
                    | _ ->
                        Location.raise_errorf ~loc:attribute.attr_loc
                          "[@@@@@@error_handler] expects a Kre.Error.handler")
                  (List.nth_opt (floating "error_handler") 0)
              @ Option.fold ~none:[]
                  ~some:(fun host -> [ (Labelled "host", estring ~loc host) ])
                  host
              @ [
                  (Labelled "spec", [%expr spec]);
                  ( Nolabel,
                    elist ~loc
                      (List.concat_map
                         (fun handler ->
                           List.map (route handler) (methods handler))
                         handlers) );
                ])
          in
          let register =
            [%stri
              let register =
                [%e
                  match dependencies with
                  | [] -> [%expr fun () -> [%e controller_value]]
                  | _ ->
                      List.fold_right
                        (fun (_, (pattern, _)) body ->
                          pexp_fun ~loc Nolabel None pattern body)
                        dependencies controller_value]]
          in
          List.rev items @ [ paths; spec; register ])

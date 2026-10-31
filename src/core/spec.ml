type verb = [ `GET | `POST | `PUT | `PATCH | `DELETE | `HEAD | `OPTIONS ]
type presence = Required | Optional | Repeated

type location =
  | Path
  | Query of presence
  | Header of presence
  | Cookie of presence

type value = { type_ : string; module_ : string; schema : Jsonkit.Jsonschema.t }

type param = {
  name : string;
  label : string;
  location : location;
  value : value;
}

type returns = Unit | Text | Json of value | Events of value | Raw

type route = {
  verb : verb;
  path : string;
  name : string;
  params : param list;
  body : value option;
  returns : returns;
  status : Dream.status;
  guards : string list;
  summary : string option;
  description : string option;
}

type t = { prefix : string; version : int option; routes : route list }

let to_json spec =
  let value_to_json value =
    `Assoc
      [
        ("type", `String value.type_);
        ("module", `String value.module_);
        ("schema", value.schema);
      ]
  in
  let param_to_json (param : param) =
    let location, presence =
      match param.location with
      | Path -> ("path", "required")
      | Query Required -> ("query", "required")
      | Query Optional -> ("query", "optional")
      | Query Repeated -> ("query", "repeated")
      | Header Required -> ("header", "required")
      | Header Optional -> ("header", "optional")
      | Header Repeated -> ("header", "repeated")
      | Cookie Required -> ("cookie", "required")
      | Cookie Optional -> ("cookie", "optional")
      | Cookie Repeated -> ("cookie", "repeated")
    in
    `Assoc
      [
        ("name", `String param.name);
        ("label", `String param.label);
        ("in", `String location);
        ("presence", `String presence);
        ("value", value_to_json param.value);
      ]
  in
  let route_to_json route =
    `Assoc
      [
        ("verb", `String (Dream.method_to_string route.verb));
        ("path", `String route.path);
        ("name", `String route.name);
        ("params", `List (List.map param_to_json route.params));
        ("body", Option.fold ~none:`Null ~some:value_to_json route.body);
        ( "returns",
          match route.returns with
          | Unit -> `String "unit"
          | Text -> `String "text"
          | Raw -> `String "raw"
          | Json value -> value_to_json value
          | Events value -> `Assoc [ ("events", value_to_json value) ] );
        ("status", `Int (Dream.status_to_int route.status));
        ("guards", `List (List.map (fun guard -> `String guard) route.guards));
        ( "summary",
          Option.fold ~none:`Null ~some:(fun s -> `String s) route.summary );
        ( "description",
          Option.fold ~none:`Null ~some:(fun s -> `String s) route.description
        );
      ]
  in
  `Assoc
    [
      ("prefix", `String spec.prefix);
      ("version", Option.fold ~none:`Null ~some:(fun v -> `Int v) spec.version);
      ("routes", `List (List.map route_to_json spec.routes));
    ]

let of_json json =
  let fail what = raise (Yojson.Basic.Util.Type_error (what, json)) in
  let open Yojson.Basic.Util in
  let value json =
    {
      type_ = to_string (member "type" json);
      module_ = to_string (member "module" json);
      schema = member "schema" json;
    }
  in
  let param json =
    {
      name = to_string (member "name" json);
      label = to_string (member "label" json);
      location =
        (match
           (to_string (member "in" json), to_string (member "presence" json))
         with
        | "path", _ -> Path
        | "query", "required" -> Query Required
        | "query", "optional" -> Query Optional
        | "query", "repeated" -> Query Repeated
        | "header", "required" -> Header Required
        | "header", "optional" -> Header Optional
        | "header", "repeated" -> Header Repeated
        | "cookie", "required" -> Cookie Required
        | "cookie", "optional" -> Cookie Optional
        | "cookie", "repeated" -> Cookie Repeated
        | location, presence -> fail (location ^ "/" ^ presence));
      value = value (member "value" json);
    }
  in
  let route json =
    {
      verb =
        (match to_string (member "verb" json) with
        | "GET" -> `GET
        | "POST" -> `POST
        | "PUT" -> `PUT
        | "PATCH" -> `PATCH
        | "DELETE" -> `DELETE
        | "HEAD" -> `HEAD
        | "OPTIONS" -> `OPTIONS
        | verb -> fail verb);
      path = to_string (member "path" json);
      name = to_string (member "name" json);
      params = List.map param (to_list (member "params" json));
      body = Option.map value (to_option Fun.id (member "body" json));
      returns =
        (match member "returns" json with
        | `String "unit" -> Unit
        | `String "text" -> Text
        | `String "raw" -> Raw
        | `Assoc [ ("events", events) ] -> Events (value events)
        | `Assoc _ as returns -> Json (value returns)
        | _ -> fail "returns");
      status = Dream.int_to_status (to_int (member "status" json));
      guards = List.map to_string (to_list (member "guards" json));
      summary = to_string_option (member "summary" json);
      description = to_string_option (member "description" json);
    }
  in
  match
    {
      prefix = to_string (member "prefix" json);
      version = to_int_option (member "version" json);
      routes = List.map route (to_list (member "routes" json));
    }
  with
  | spec -> Ok spec
  | exception Type_error (message, culprit) ->
      Error (message ^ ": " ^ Yojson.Basic.to_string culprit)

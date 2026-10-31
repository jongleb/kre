type verb = [ `GET | `POST | `PUT | `PATCH | `DELETE ]
type presence = Required | Optional | Repeated
type location = Path | Query of presence
type value = { type_ : string; module_ : string; schema : Jsonkit.Jsonschema.t }
type param = { name : string; location : location; value : value }
type returns = Unit | Text | Json of value | Raw

type route = {
  verb : verb;
  path : string;
  name : string;
  params : param list;
  body : value option;
  returns : returns;
  status : Dream.status;
  guards : string list;
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
    in
    `Assoc
      [
        ("name", `String param.name);
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
          | Json value -> value_to_json value );
        ("status", `Int (Dream.status_to_int route.status));
        ("guards", `List (List.map (fun guard -> `String guard) route.guards));
      ]
  in
  `Assoc
    [
      ("prefix", `String spec.prefix);
      ("version", Option.fold ~none:`Null ~some:(fun v -> `Int v) spec.version);
      ("routes", `List (List.map route_to_json spec.routes));
    ]

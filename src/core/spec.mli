type verb = [ `GET | `POST | `PUT | `PATCH | `DELETE ]

type presence =
  | Required
  | Optional  (** May be absent; a default, if any, is in the schema. *)
  | Repeated  (** [?x=a&x=b]. *)

type location = Path | Query of presence

type dto = { name : string; schema : Jsonkit.Jsonschema.t }
(** A JSON type, named by its OCaml module. *)

type param = {
  name : string;
  location : location;
  scalar : string;  (** [Forge_shared.Scalar.S.name] of the parameter type. *)
  schema : Jsonkit.Jsonschema.t;
}

type returns = Unit | Text | Json of dto | Raw

type route = {
  verb : verb;
  path : string;  (** Full path with the controller prefix, [:name] segments. *)
  name : string;  (** The handler. *)
  params : param list;
  body : dto option;
  returns : returns;
  status : Dream.status;
  guards : string list;  (** Guard expressions, for documentation only. *)
}

type t = { prefix : string; version : int option; routes : route list }
(** Runtime description of a controller; source for clients and OpenAPI. *)

val to_json : t -> Jsonkit.t

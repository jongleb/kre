type verb = [ `GET | `POST | `PUT | `PATCH | `DELETE ]

type presence =
  | Required
  | Optional  (** May be absent; a default, if any, is in the schema. *)
  | Repeated  (** [?x=a&x=b]. *)

type location = Path | Query of presence

type value = {
  type_ : string;  (** The OCaml type as written, e.g. ["Cat.t list"]. *)
  module_ : string;
      (** Its [Json.S] or [Scalar.S] module, e.g.
          ["Forge_shared.Json.List (Cat)"]. *)
  schema : Jsonkit.Jsonschema.t;
}
(** A value crossing the wire, described for code generators. *)

type param = { name : string; location : location; value : value }
type returns = Unit | Text | Json of value | Events of value | Raw

type route = {
  verb : verb;
  path : string;  (** Full path with the controller prefix, [:name] segments. *)
  name : string;  (** The handler. *)
  params : param list;
  body : value option;
  returns : returns;
  status : Dream.status;
  guards : string list;  (** Guard expressions, for documentation only. *)
}

type t = { prefix : string; version : int option; routes : route list }
(** Runtime description of a controller; source for clients and OpenAPI. *)

val to_json : t -> Jsonkit.t
val of_json : Jsonkit.t -> (t, string) result

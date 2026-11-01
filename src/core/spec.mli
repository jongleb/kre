type verb = [ `GET | `POST | `PUT | `PATCH | `DELETE | `HEAD | `OPTIONS ]

type presence =
  | Required
  | Optional  (** May be absent; a default, if any, is in the schema. *)
  | Repeated  (** [?x=a&x=b]. *)

type location =
  | Path
  | Query of presence
  | Header of presence
  | Cookie of presence
  | Search  (** The whole query string, read into a record by its codec. *)

type value = {
  type_ : string;  (** The OCaml type as written, e.g. ["Cat.t list"]. *)
  module_ : string;
      (** Its [Json.S] or [Scalar.S] module, e.g.
          ["Kre_shared.Json.List (Cat)"]. *)
  schema : Jsonkit.Jsonschema.t;
}
(** A value crossing the wire, described for code generators. *)

type param = {
  name : string;  (** On the wire: segment, query key, header or cookie name. *)
  label : string;  (** The handler's label, e.g. [client_name]. *)
  location : location;
  value : value;
}

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
  summary : string option;  (** [[@@summary]]: OpenAPI operation summary. *)
  description : string option;  (** [[@@description]]. *)
  live : string list;  (** [[@@live]]: tables whose changes reload the page. *)
}

type t = { prefix : string; version : int option; routes : route list }
(** Runtime description of a controller; source for clients and OpenAPI. *)

val to_json : t -> Jsonkit.t
val of_json : Jsonkit.t -> (t, string) result

type exchange = {
  verb : Wire.verb;
  target : string;  (** Path and query, without the base URL. *)
  headers : (string * string) list;
  body : string option;
}
(** One request as a generated client sends it. *)

(** Where requests go: [Network] through cohttp to [base_url], [Local] to a
    function, such as the application inside a test. *)
type transport = Network | Local of (exchange -> Wire.response Lwt.t)

val transport : transport ref
val base_url : string ref
val headers : (string * string) list ref

val request :
  Wire.verb ->
  path:string list ->
  ?query:(string * string) list list ->
  ?headers:(string * string) list list ->
  ?body:string ->
  'a Wire.returns ->
  ('a, Error.t) result Lwt.t

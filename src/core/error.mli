type status = [ Dream.client_error | Dream.server_error | `Unprocessable_Entity ]
(** Only 4xx and 5xx; Dream has no constructor for 422, so it is added here. *)

type t = private {
  status : status;
  code : string;  (** Short machine name, also the tail of [type_]. *)
  type_ : string;  (** RFC 9457 [type] URI. *)
  detail : string;
  extensions : (string * Jsonkit.t) list;
      (** Extra top-level Problem Details members. *)
}
(** An HTTP error, serialised as RFC 9457 Problem Details. *)

exception E of t

val make :
  status:status ->
  code:string ->
  ?type_:string ->
  ?extensions:(string * Jsonkit.t) list ->
  string ->
  t

val bad_request : ?extensions:(string * Jsonkit.t) list -> string -> t
val unauthorized : string -> t
val forbidden : string -> t
val not_found : string -> t
val conflict : string -> t
val unprocessable : Forge_shared.Validation.t -> t
val internal : string -> t
val to_json : instance:string -> t -> Jsonkit.t
val to_response : Dream.request -> t -> Dream.response Lwt.t
val fail : t -> 'a Lwt.t

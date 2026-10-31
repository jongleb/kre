type claims = private {
  subject : string;
  expires : float;  (** Unix time. *)
  extra : (string * Jsonkit.t) list;  (** Other members of the payload. *)
}
(** A verified HS256 token. *)

type error = Malformed | Bad_signature | Expired

val sign :
  secret:string ->
  ?now:float ->
  ?extra:(string * Jsonkit.t) list ->
  expires_in:float ->
  string ->
  string

val verify :
  secret:string -> ?now:float -> string -> (claims, [> `Jwt of error ]) result

val bearer : secret:string -> claims Guard.t

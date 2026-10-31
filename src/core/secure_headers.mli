(** Whether to send Strict-Transport-Security; only behind HTTPS. *)
type transport = Https_only of { max_age : int } | Any_transport

val middleware :
  ?content_security_policy:string ->
  ?transport:transport ->
  unit ->
  Dream.middleware

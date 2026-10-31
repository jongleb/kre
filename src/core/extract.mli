val req : Dream.request Guard.t
val ip : string Guard.t
val host : string Guard.t
val headers : (string * string) list Guard.t
val queries : (string * string) list Guard.t
val cookies : (string * string) list Guard.t

val header :
  (module S : Forge_shared.Scalar.S) ->
  (S.t, 'b) Forge_shared.Presence.t -> string -> 'b Guard.t

val cookie :
  (module S : Forge_shared.Scalar.S) ->
  (S.t, 'b) Forge_shared.Presence.t -> string -> 'b Guard.t

val signed_cookie :
  (module S : Forge_shared.Scalar.S) ->
  (S.t, 'b) Forge_shared.Presence.t -> string -> 'b Guard.t

val session :
  (module S : Forge_shared.Scalar.S) ->
  (S.t, 'b) Forge_shared.Presence.t -> string -> 'b Guard.t

val body_field : (module J : Forge_shared.Json.S) -> string -> J.t Guard.t

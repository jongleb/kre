val req : Dream.request Guard.t
val ip : string Guard.t
val host : string Guard.t
val headers : (string * string) list Guard.t
val queries : (string * string) list Guard.t
val cookies : (string * string) list Guard.t

val header :
  (module S : Kre_shared.Scalar.S) ->
  (S.t, 'b) Kre_shared.Presence.t -> string -> 'b Guard.t

val cookie :
  (module S : Kre_shared.Scalar.S) ->
  (S.t, 'b) Kre_shared.Presence.t -> string -> 'b Guard.t

val signed_cookie :
  (module S : Kre_shared.Scalar.S) ->
  (S.t, 'b) Kre_shared.Presence.t -> string -> 'b Guard.t

val session :
  (module S : Kre_shared.Scalar.S) ->
  (S.t, 'b) Kre_shared.Presence.t -> string -> 'b Guard.t

val search : 's Kre_shared.Search.t -> 's Guard.t
val body_field : (module J : Kre_shared.Json.S) -> string -> J.t Guard.t
val host_param : pattern:string -> string -> string Guard.t
val file : string -> Upload.t Guard.t
val files : string -> Upload.t list Guard.t

val form :
  (module S : Kre_shared.Scalar.S) ->
  (S.t, 'b) Kre_shared.Presence.t -> string -> 'b Guard.t

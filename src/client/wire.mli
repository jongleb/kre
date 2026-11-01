type verb = [ `GET | `POST | `PUT | `PATCH | `DELETE | `HEAD | `OPTIONS ]
type response = { status : int; body : string }

(** How an answer becomes the value a generated client function returns. *)
type 'a returns =
  | Unit : unit returns
  | Text : string returns
  | Json : (module Forge_shared.Json.S with type t = 'a) -> 'a returns
  | Raw : response returns

val method_name : verb -> string
val segment : (module S : Forge_shared.Scalar.S) -> S.t -> string

val query :
  (module S : Forge_shared.Scalar.S) ->
  (S.t, 'b) Forge_shared.Presence.t -> string -> 'b -> (string * string) list

val search : 's Forge_shared.Search.t -> 's -> (string * string) list
val body : (module J : Forge_shared.Json.S) -> J.t -> string

val url :
  base:string -> path:string list -> query:(string * string) list list -> string

val decode : 'a returns -> response -> ('a, Error.t) result

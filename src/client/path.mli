type 'p t
(** A page path whose [:name] segments decode to ['p]. *)

val static : string -> unit t

val make :
  string ->
  decode:((string * string) list -> ('p, Forge_shared.Validation.t) result) ->
  encode:('p -> (string * string) list) ->
  'p t

val param :
  (module S : Forge_shared.Scalar.S) ->
  string -> (string * string) list -> (S.t, Forge_shared.Validation.t) result

val match_ : 'p t -> string list -> 'p option
val print : 'p t -> 'p -> string

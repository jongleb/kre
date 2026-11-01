type 'p t
(** A page path whose [:name] segments decode to ['p]. *)

val static : string -> unit t

val make :
  string ->
  decode:((string * string) list -> ('p, Kre_shared.Validation.t) result) ->
  encode:('p -> (string * string) list) ->
  'p t

val param :
  (module S : Kre_shared.Scalar.S) ->
  string -> (string * string) list -> (S.t, Kre_shared.Validation.t) result

val match_ : 'p t -> string list -> 'p option
val print : 'p t -> 'p -> string

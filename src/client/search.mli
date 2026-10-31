type 's t
(** How a page's query string decodes to ['s] and prints back. *)

(** Whether a query parameter must be present, and what the field holds. *)
type ('a, 'b) presence =
  | Required : ('a, 'a) presence
  | Optional : ('a, 'a option) presence
  | Default : 'a -> ('a, 'a) presence
  | Repeated : ('a, 'a list) presence

type 'a field
(** One query parameter of a search record. *)

val none : unit t

val field :
  string -> (module S : Forge_shared.Scalar.S) -> (S.t, 'b) presence -> 'b field

val read :
  'a field -> (string * string) list -> ('a, Forge_shared.Validation.t) result

val show : 'a field -> 'a -> (string * string) list

val make :
  parse:((string * string) list -> ('s, Forge_shared.Validation.t) result) ->
  print:('s -> (string * string) list list) ->
  's t

val parse : 's t -> string -> ('s, Forge_shared.Validation.t) result
val print : 's t -> 's -> string

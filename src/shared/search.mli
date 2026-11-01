type 's t
(** How a query string decodes to ['s] and back: a search record, shared by the
    server, the client and the page router. *)

(** Whether a query parameter must be present, and what the field holds. *)
type ('a, 'b) presence =
  | Required : ('a, 'a) presence
  | Optional : ('a, 'a option) presence
  | Default : 'a -> ('a, 'a) presence
  | Repeated : ('a, 'a list) presence

type 'a field
(** One query parameter of a search record. *)

val none : unit t
val field : string -> (module S : Scalar.S) -> (S.t, 'b) presence -> 'b field
val read : 'a field -> (string * string) list -> ('a, Validation.t) result
val show : 'a field -> 'a -> (string * string) list

val make :
  parse:((string * string) list -> ('s, Validation.t) result) ->
  print:('s -> (string * string) list list) ->
  's t

val decode : 's t -> (string * string) list -> ('s, Validation.t) result
val encode : 's t -> 's -> (string * string) list

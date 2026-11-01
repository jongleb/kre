type t
(** An instant, in UTC; RFC 3339 on the wire, seconds in the database. *)

include Scalar.S with type t := t

val of_seconds : float -> t
val to_seconds : t -> float
val compare : t -> t -> int

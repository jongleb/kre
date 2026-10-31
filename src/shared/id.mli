(** An entity identifier: parsing, the database or [succ] make one. *)
module type S = sig
  include Refined.S with type repr = int

  val first : t
  val succ : t -> t
  val equal : t -> t -> bool
end

module Make () : S
(** A new identifier type, distinct from every other entity's. *)

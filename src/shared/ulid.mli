(** A ULID-keyed entity id: 26 Crockford base32 characters, sortable by time. *)
module type S = sig
  include Refined.S with type repr = string

  val equal : t -> t -> bool
end

module Make () : S
(** A new ULID id type, distinct from every other entity's. *)

val alphabet : string

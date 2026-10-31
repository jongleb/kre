(** An opaque type whose every value passed its rules. *)
module type S = sig
  type t
  type repr

  include Scalar.S with type t := t

  val of_repr : repr -> (t, Validation.t) result
  val to_repr : t -> repr
  val pp : Format.formatter -> t -> unit
end

(** Rules and JSON Schema keywords that refine a base scalar. *)
module type RULES = sig
  type base

  val name : string
  val rules : base Validation.rule list
  val constraints : (string * Jsonkit.Jsonschema.t) list
end

module Make (Base : Scalar.S) (C : RULES with type base := Base.t) :
  S with type repr = Base.t

module String (C : sig
  val name : string
  val min : int
  val max : int
end) : S with type repr = string

module Int (C : sig
  val name : string
  val min : int
  val max : int
end) : S with type repr = int

module Enum (C : sig
  val name : string
  val values : string list
end) : S with type repr = string

module Email : S with type repr = string

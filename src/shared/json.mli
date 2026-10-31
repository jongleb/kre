(** A type with jsonkit-style converters; [of_json] raises on bad input. *)
module type S = sig
  type t

  val of_json : Jsonkit.t -> t
  val to_json : t -> Jsonkit.t
  val t_jsonschema : Jsonkit.Jsonschema.t
end

val parse : (module J : S) -> Jsonkit.t -> (J.t, Validation.t) result
val omit : string list -> Jsonkit.t -> Jsonkit.t
val write_only : string list -> Jsonkit.Jsonschema.t -> Jsonkit.Jsonschema.t

module Ignored : S with type t = unit
(** Any JSON, read as [()]: the body of an event that carries none. *)

(** A JSON array of [J.t]. *)
module List (J : S) : S with type t = J.t list

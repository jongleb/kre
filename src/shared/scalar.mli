(** A value that travels both as JSON and as one path or query segment. *)
module type S = sig
  type t

  include Json.S with type t := t

  val name : string
  val of_string : string -> (t, Validation.t) result
  val to_string : t -> string
end

module Int : S with type t = int
module Int64 : S with type t = int64
module Float : S with type t = float
module Bool : S with type t = bool
module String : S with type t = string

val length : string -> int

(** A regular expression, compiled by the backend's own engine. *)
module Pattern : sig
  type t

  val of_string : string -> (t, string) result
  val matching : t -> string -> string option
end

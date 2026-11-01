type problem = {
  status : int;
  type_ : string;
  title : string;
  detail : string;
  errors : Kre_shared.Validation.error list;  (** Field failures of a 422. *)
}
(** An RFC 9457 Problem Details answer from a Kre server. *)

type t =
  | Problem of problem
  | Network of string  (** The request never got an answer. *)
  | Decode of Kre_shared.Validation.t  (** The answer did not match its type. *)

val of_response : status:int -> string -> t
val message : t -> string

type error = { path : string list; rule : string; message : string }
(** One failed rule, located by the JSON path of the rejected value. *)

type t = private { first : error; rest : error list }
(** A non-empty set of failures. *)

exception Invalid of t
(** Raised by jsonkit-style decoders; [Json.parse] turns it into a result. *)

type 'a rule
(** A named check that keeps the value or explains why it is rejected. *)

val fail : rule:string -> string -> t
val ok_exn : ('a, t) result -> 'a
val at : string list -> t -> t
val to_list : t -> error list
val to_json : t -> Jsonkit.t
val rule : name:string -> ('a -> ('a, string) result) -> 'a rule
val check : 'a rule list -> 'a -> ('a, t) result
val field : string -> 'a rule list -> 'a -> ('a, t) result

(** Applicative composition: [and+] keeps the failures of both sides. *)
module Syntax : sig
  val ( let+ ) : ('a, t) result -> ('a -> 'b) -> ('b, t) result
  val ( and+ ) : ('a, t) result -> ('b, t) result -> ('a * 'b, t) result
end

val min_length : int -> string rule
val max_length : int -> string rule
val min : int -> int rule
val max : int -> int rule
val range : min:int -> max:int -> int rule
val one_of : string list -> string rule
val email : string rule

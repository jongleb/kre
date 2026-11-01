type 'a t = Dream.request -> ('a, Error.t) result Lwt.t
(** Extracts a value from the request or rejects it. *)

val field : 'a Dream.field -> missing:Error.t -> 'a t
val header : string -> string t
val both : 'a t -> 'b t -> ('a * 'b) t
val session : string -> string t
val map : ('a -> 'b) -> 'a t -> 'b t
val check : ('a -> ('b, Error.t) result) -> 'a t -> 'b t
val optional : 'a t -> 'a option t

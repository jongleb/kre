type 'a t = Dream.request -> ('a, Error.t) result Lwt.t
(** Extracts a value from the request or rejects it; Nest guards and param
    decorators. *)

val field : 'a Dream.field -> missing:Error.t -> 'a t
val header : string -> string t
val both : 'a t -> 'b t -> ('a * 'b) t

type t
(** A static file checked at build time; its URL carries the content hash. *)

val checked : string -> t
val url : t -> string

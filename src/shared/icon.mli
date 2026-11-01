type t
(** An SVG icon read from assets/icons at build time. *)

val checked : name:string -> string -> t
val name : t -> string
val svg : t -> string

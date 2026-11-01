(** Changes pushed by the server's [/__kre/live] channel. *)

val watch : string list -> (string -> unit) -> unit -> unit

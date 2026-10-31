(** Changes pushed by the server's [/__forge/live] channel. *)

val watch : string list -> (string -> unit) -> unit -> unit

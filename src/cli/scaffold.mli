(** What [forge generate] writes. *)
type kind = Controller | Service | Dto

val project : string -> (string list, string) result
val generate : kind -> string -> (string list, string) result

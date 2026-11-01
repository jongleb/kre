(** What [kre generate] writes. *)
type kind = Controller | Service | Dto

val project : string -> (string list, string) result

val generate :
  kind -> string -> fields:string list -> (string list, string) result

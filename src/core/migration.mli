type t = private { version : string; up : string list; down : string list }
(** One file of [migrations/]: its name and the statements of each section. *)

(** Whether a migration has run on the database. *)
type state = Applied | Pending

val parse : version:string -> string -> (t, string) result
val load : string -> (t list, string) result
val create : dir:string -> string -> string

val status :
  (module D : Db.DRIVER) -> D.conn -> t list -> (t * state) list Lwt.t

val up : (module D : Db.DRIVER) -> D.conn -> t list -> t list Lwt.t
val down : (module D : Db.DRIVER) -> D.conn -> t list -> t option Lwt.t

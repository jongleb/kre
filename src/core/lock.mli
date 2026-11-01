val table : Table.t

(** Locks shared by every process that uses the same database: a provider. *)
module type S = sig
  val exclusive : ?ttl:float -> string -> (unit -> unit Lwt.t) -> unit Lwt.t
end

module Make (Db : Db.S) : S

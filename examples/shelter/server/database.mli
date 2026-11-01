(** The connection pool, migrated on start. *)
module Make (Settings : Settings.S) : sig
  include Forge.Db.S with type conn = Forge_db_mariadb.Client.t

  val on_start : unit -> unit Lwt.t
  val ping : unit -> (unit, string) result Lwt.t
end

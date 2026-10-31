module Make (Db : Forge.Db.S with type conn = Forge_db_mariadb.Client.t) : sig
  include Cats_service.S

  val reset : unit -> unit Lwt.t
end

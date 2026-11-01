module Make (Db : Kre.Db.S with type conn = Kre_db_mariadb.Client.t) : sig
  include Cats_service.S

  val reset : unit -> unit Lwt.t
end

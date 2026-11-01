(** The cats of the shelter. *)
module type S = sig
  val available : unit -> Cat.t list Lwt.t
  val find : Cat.Id.t -> Cat.t option Lwt.t
  val create : Create_cat_dto.t -> Cat.t Lwt.t
  val rename : Cat.Id.t -> Cat.Name.t -> (Cat.t, Forge.Error.t) result Lwt.t

  val adopt :
    conn:Forge_db_mariadb.Client.t ->
    Cat.Id.t ->
    User.Id.t ->
    (unit, Forge.Error.t) result Lwt.t
end

module Make (Db : Forge.Db.S with type conn = Forge_db_mariadb.Client.t) : S

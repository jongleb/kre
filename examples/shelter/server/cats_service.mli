(** The cats of the shelter. *)
module type S = sig
  val available : unit -> Cat.t list Lwt.t
  val find : Cat.Id.t -> Cat.t option Lwt.t

  val catalog :
    Cat_filter.t -> Kre_shared.Page.Request.t -> Cat.t Kre_shared.Page.t Lwt.t

  val owned_by : User.Id.t list -> (User.Id.t -> Cat.t list) Lwt.t
  val create : Create_cat_dto.t -> Cat.t Lwt.t
  val rename : Cat.Id.t -> Rename_dto.t -> (Cat.t, Kre.Error.t) result Lwt.t
  val adopt : Cat.Id.t -> User.Id.t -> (unit, Kre.Error.t) result Lwt.t
end

module Make (Db : Kre.Db.S with type conn = Kre_db_mariadb.Client.t) : S

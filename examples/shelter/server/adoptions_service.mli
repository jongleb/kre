(** Adoptions: a member takes a cat home, at most two of them. *)
module type S = sig
  val adopt : Cat.Id.t -> User.Id.t -> (Adoption.t, Forge.Error.t) result Lwt.t
  val of_user : User.Id.t -> Adoption.t list Lwt.t
end

module Make
    (Db : Forge.Db.S with type conn = Forge_db_mariadb.Client.t)
    (Cats : Cats_service.S) : S

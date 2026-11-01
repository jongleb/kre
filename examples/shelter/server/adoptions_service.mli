(** Adoptions: a member takes a cat home, at most two of them, and gets a
    letter. *)
module type S = sig
  val adopt : Cat.Id.t -> User.Id.t -> (Adoption.t, Kre.Error.t) result Lwt.t
  val of_user : User.Id.t -> Adoption.t list Lwt.t
end

module Make
    (Db : Kre.Db.S with type conn = Kre_db_mariadb.Client.t)
    (Cats : Cats_service.S)
    (Jobs : Kre.Job.S) : S

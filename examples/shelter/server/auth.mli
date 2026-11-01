(** Proof that the caller is an admin; only [admin] makes one. *)
module Admin : sig
  type t
end

val session : User.t -> Session.t
val current : User.t Kre.Guard.t
val admin : Admin.t Kre.Guard.t
val owner_or_admin : user:User.t -> Cat.t -> (unit, Kre.Error.t) result Lwt.t

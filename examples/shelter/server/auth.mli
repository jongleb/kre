(** Proof that the caller is an admin; only [admin] makes one. *)
module Admin : sig
  type t
end

val session : User.t -> Session.t
val current : User.t Forge.Guard.t
val admin : Admin.t Forge.Guard.t
val owner_or_admin : user:User.t -> Cat.t -> (unit, Forge.Error.t) result Lwt.t

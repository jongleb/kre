(** Accounts: sign up, and log in with a password. *)
module type S = sig
  val signup : Login_dto.t -> (User.t, Forge.Error.t) result Lwt.t
  val login : Login_dto.t -> User.t option Lwt.t
end

module Make
    (Settings : Settings.S)
    (Db : Forge.Db.S with type conn = Forge_db_mariadb.Client.t) : S

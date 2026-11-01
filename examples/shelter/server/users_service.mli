(** Accounts: sign up, and log in with a password. *)
module type S = sig
  val signup : Login_dto.t -> (User.t, Kre.Error.t) result Lwt.t

  val unused :
    Kre_shared.Refined.Email.t -> (unit, Kre_shared.Validation.t) result Lwt.t

  val login : Login_dto.t -> User.t option Lwt.t
end

module Make
    (Settings : Settings.S)
    (Db : Kre.Db.S with type conn = Kre_db_mariadb.Client.t) : S

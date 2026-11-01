module type S = sig
  val signup : Login_dto.t -> (User.t, Kre.Error.t) result Lwt.t

  val unused :
    Kre_shared.Refined.Email.t -> (unit, Kre_shared.Validation.t) result Lwt.t

  val login : Login_dto.t -> User.t option Lwt.t
end

module Make
    (Settings : Settings.S)
    (Db : Kre.Db.S with type conn = Kre_db_mariadb.Client.t) : S = struct
  module Sql = Shelter_sql.Make (Kre_db_mariadb.Sql)
  module Users = Users_crud.Make (Kre_db_mariadb.Sql)
  module Credentials = Credentials_crud.Make (Kre_db_mariadb.Sql)

  let signup ({ email; password } : Login_dto.t) =
    Db.transaction (fun conn ->
        let address = Kre_shared.Refined.Email.to_string email in
        match%lwt Users.Single.by_email conn ~email:address User.of_row with
        | Some _ -> Lwt.return_error (Kre.Error.conflict "this email is taken")
        | None ->
            let role =
              Option.fold ~none:User.Role.Member
                ~some:(fun admin ->
                  match
                    String.equal address
                      (Kre_shared.Refined.Email.to_string admin)
                  with
                  | true -> User.Role.Admin
                  | false -> Member)
                Settings.config.admin_email
            in
            let%lwt inserted =
              Users.insert conn ~email:address ~role:(User.Role.to_string role)
            in
            let%lwt id = Inserted.id (module User.Id) inserted in
            let%lwt _ =
              Credential.for_insert
                (Credential.make ~user_id:id ~password)
                (Credentials.insert conn)
            in
            Lwt.return_ok { User.id; email; role })

  let unused email =
    Db.with_conn (fun conn ->
        Lwt.map
          (Option.fold ~none:(Ok ()) ~some:(fun _ ->
               Error
                 (Kre_shared.Validation.at [ "email" ]
                    (Kre_shared.Validation.fail ~rule:"unique"
                       "this email is taken"))))
          (Users.Single.by_email conn
             ~email:(Kre_shared.Refined.Email.to_string email)
             User.of_row))

  let login ({ email; password } : Login_dto.t) =
    Db.with_conn (fun conn ->
        let%lwt credential =
          Sql.Single.credential_by_email conn
            ~email:(Kre_shared.Refined.Email.to_string email)
            Credential.of_row
        in
        Option.fold ~none:Lwt.return_none
          ~some:(fun id ->
            Users.Single.find conn
              ~id:(Int64.of_int (User.Id.to_repr id))
              User.of_row)
          (Option.bind credential (Credential.verify ~password)))
end

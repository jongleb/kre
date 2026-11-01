module Admin = struct
  type t = Admin
end

let session (user : User.t) =
  {
    Session.token =
      Kre.Jwt.sign ~secret:Settings.config.jwt_secret ~expires_in:3600.
        ~extra:[ ("user", User.to_json user) ]
        (User.Id.to_string user.id);
    user;
  }

let current =
  Kre.Guard.check
    (fun (claims : Kre.Jwt.claims) ->
      Option.fold
        ~none:(Error (Kre.Error.unauthorized "the token carries no user"))
        ~some:(fun json ->
          Result.map_error
            (fun _ -> Kre.Error.unauthorized "the token carries no user")
            (Kre_shared.Json.parse (module User) json))
        (List.assoc_opt "user" claims.extra))
    (Kre.Jwt.bearer ~secret:Settings.config.jwt_secret)

let admin =
  Kre.Guard.check
    (fun (user : User.t) ->
      match user.role with
      | Admin -> Ok Admin.Admin
      | Member -> Error (Kre.Error.forbidden "admins only"))
    current

let owner_or_admin ~(user : User.t) (cat : Cat.t) =
  Lwt.return
    (match (cat.owner_id, user.role) with
    | _, Admin -> Ok ()
    | Some owner, Member when User.Id.equal owner user.id -> Ok ()
    | (Some _ | None), Member ->
        Error (Kre.Error.forbidden "only its owner or an admin renames a cat"))

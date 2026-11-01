module Admin = struct
  type t = Admin
end

let session (user : User.t) =
  {
    Session.token =
      Forge.Jwt.sign ~secret:Settings.config.jwt_secret ~expires_in:3600.
        ~extra:[ ("user", User.to_json user) ]
        (User.Id.to_string user.id);
    user;
  }

let current =
  Forge.Guard.check
    (fun (claims : Forge.Jwt.claims) ->
      Option.fold
        ~none:(Error (Forge.Error.unauthorized "the token carries no user"))
        ~some:(fun json ->
          Result.map_error
            (fun _ -> Forge.Error.unauthorized "the token carries no user")
            (Forge_shared.Json.parse (module User) json))
        (List.assoc_opt "user" claims.extra))
    (Forge.Jwt.bearer ~secret:Settings.config.jwt_secret)

let admin =
  Forge.Guard.check
    (fun (user : User.t) ->
      match user.role with
      | Admin -> Ok Admin.Admin
      | Member -> Error (Forge.Error.forbidden "admins only"))
    current

let owner_or_admin ~(user : User.t) (cat : Cat.t option) =
  match (cat, user.role) with
  | None, _ -> Error (Forge.Error.not_found "cat")
  | Some _, Admin -> Ok ()
  | Some { owner_id = Some owner; _ }, Member when User.Id.equal owner user.id
    ->
      Ok ()
  | Some _, Member ->
      Error (Forge.Error.forbidden "only its owner or an admin renames a cat")

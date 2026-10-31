let secret = "change-me"

module Admin : sig
  type t

  val of_claims : Forge.Jwt.claims -> (t, Forge.Error.t) result
end = struct
  type t = Admin

  let of_claims (claims : Forge.Jwt.claims) =
    match List.assoc_opt "role" claims.extra with
    | Some (`String "admin") -> Ok Admin
    | Some _ | None -> Error (Forge.Error.forbidden "admins only")
end

let user : Forge.Jwt.claims Forge.Guard.t = Forge.Jwt.bearer ~secret
let admin : Admin.t Forge.Guard.t = Forge.Guard.check Admin.of_claims user

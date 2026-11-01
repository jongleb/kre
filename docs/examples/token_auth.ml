let secret = "change-me"

module Admin : sig
  type t

  val of_claims : Kre.Jwt.claims -> (t, Kre.Error.t) result
end = struct
  type t = Admin

  let of_claims (claims : Kre.Jwt.claims) =
    match List.assoc_opt "role" claims.extra with
    | Some (`String "admin") -> Ok Admin
    | Some _ | None -> Error (Kre.Error.forbidden "admins only")
end

let user : Kre.Jwt.claims Kre.Guard.t = Kre.Jwt.bearer ~secret
let admin : Admin.t Kre.Guard.t = Kre.Guard.check Admin.of_claims user

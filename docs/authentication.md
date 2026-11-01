# Authentication and Authorization

In Kre an authentication strategy is a guard. `Kre.Jwt.bearer ~secret` checks an HS256 token from `Authorization: Bearer …` and returns `Kre.Jwt.claims`; `Kre.Guard.session "user_id"` reads a Dream session field. A role is `Kre.Guard.check`, which turns claims into evidence: there is no other way to get a value of `Admin.t`.

<!-- $MDX file=examples/token_auth.ml -->
```ocaml
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
```

Issuing a token and an admin-only route:

<!-- $MDX file=examples/session_controller.ml -->
```ocaml
[@@@controller "session"]

let login ~(body : Login.t) () : (string, Kre.Error.t) result Lwt.t =
  Lwt.return
    (match (body.user, body.password) with
    | "root", "secret" ->
        Ok
          (Kre.Jwt.sign ~secret:Token_auth.secret ~expires_in:3600.
             ~extra:[ ("role", `String "admin") ]
             "root")
    | _ -> Error (Kre.Error.unauthorized "bad credentials"))
[@@post "login"]

let reset ~admin:(_ : (Token_auth.Admin.t[@guard Token_auth.admin])) () :
    unit Lwt.t =
  Lwt.return_unit
[@@post "reset"]
```

`Kre.Jwt.verify` returns `(claims, [> `Jwt of Malformed | Bad_signature | Expired ]) result`; the signature is compared in constant time. Password hashing is up to the application (argon2, bcrypt).

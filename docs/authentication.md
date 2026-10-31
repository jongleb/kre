# Authentication и Authorization

Nest: Passport-стратегии, `JwtAuthGuard`, `@Roles()` и `RolesGuard`. Forge: стратегия — это guard. `Forge.Jwt.bearer ~secret` проверяет HS256-токен из `Authorization: Bearer …` и отдаёт `Forge.Jwt.claims`; `Forge.Guard.session "user_id"` читает поле сессии Dream. Роль — `Forge.Guard.check`, который превращает claims в доказательство: значение `Admin.t` получить больше негде.

<!-- $MDX file=examples/token_auth.ml -->
```ocaml
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
```

Выдача токена и маршрут только для админа:

<!-- $MDX file=examples/session_controller.ml -->
```ocaml
[@@@controller "session"]

let login ~(body : Login.t) () : (string, Forge.Error.t) result Lwt.t =
  Lwt.return
    (match (body.user, body.password) with
    | "root", "secret" ->
        Ok
          (Forge.Jwt.sign ~secret:Token_auth.secret ~expires_in:3600.
             ~extra:[ ("role", `String "admin") ]
             "root")
    | _ -> Error (Forge.Error.unauthorized "bad credentials"))
[@@post "login"]

let reset ~admin:(_ : (Token_auth.Admin.t[@guard Token_auth.admin])) () :
    unit Lwt.t =
  Lwt.return_unit
[@@post "reset"]
```

`Forge.Jwt.verify` возвращает `(claims, [> `Jwt of Malformed | Bad_signature | Expired ]) result`; подпись сравнивается за постоянное время. Хеширование паролей — дело приложения (argon2, bcrypt).

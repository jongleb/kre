# Authentication и Authorization

Nest: Passport-стратегии, `JwtAuthGuard`, `@Roles()` и `RolesGuard`. Kre: стратегия — это guard. `Kre.Jwt.bearer ~secret` проверяет HS256-токен из `Authorization: Bearer …` и отдаёт `Kre.Jwt.claims`; `Kre.Guard.session "user_id"` читает поле сессии Dream. Роль — `Kre.Guard.check`, который превращает claims в доказательство: значение `Admin.t` получить больше негде.

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

Выдача токена и маршрут только для админа:

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

`Kre.Jwt.verify` возвращает `(claims, [> `Jwt of Malformed | Bad_signature | Expired ]) result`; подпись сравнивается за постоянное время. Хеширование паролей — дело приложения (argon2, bcrypt).

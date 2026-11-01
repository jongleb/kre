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

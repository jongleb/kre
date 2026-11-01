[@@@controller "auth"]

let signup (module Users : Users_service.S) ~(body : Login_dto.t) :
    (Session.t, Kre.Error.t) result Lwt.t =
  Lwt_result.map Auth.session (Users.signup body)
[@@post "signup"]
[@@status 201]
[@@check fun ~body -> Users.unused body.Login_dto.email]
[@@summary "Create an account"]

let login (module Users : Users_service.S) ~(body : Login_dto.t) :
    (Session.t, Kre.Error.t) result Lwt.t =
  Lwt.map
    (fun user ->
      Option.to_result
        ~none:(Kre.Error.unauthorized "wrong email or password")
        (Option.map Auth.session user))
    (Users.login body)
[@@post "login"] [@@summary "Trade a password for a token"]

let me ~(user : (User.t[@guard Auth.current])) () : User.t Lwt.t =
  Lwt.return user
[@@get "me"]

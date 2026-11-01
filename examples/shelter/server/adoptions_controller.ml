[@@@controller "adoptions"]

let adopt (module Adoptions : Adoptions_service.S)
    (module Db : Forge.Db.S with type conn = Forge_db_mariadb.Client.t)
    ~(user : (User.t[@guard Auth.current]))
    ~(conn : (Forge_db_mariadb.Client.t[@from Db.tx])) ~(body : Adopt_dto.t) :
    (Adoption.t, Forge.Error.t) result Lwt.t =
  Adoptions.adopt ~conn body.cat_id user.id
[@@post] [@@status 201] [@@transactional] [@@summary "Take a cat home"]

let mine (module Adoptions : Adoptions_service.S)
    ~(user : (User.t[@guard Auth.current])) () : Adoption.t list Lwt.t =
  Adoptions.of_user user.id
[@@get "mine"] [@@live [ "adoptions" ]]

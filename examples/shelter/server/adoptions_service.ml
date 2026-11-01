module type S = sig
  val adopt : Cat.Id.t -> User.Id.t -> (Adoption.t, Forge.Error.t) result Lwt.t
  val of_user : User.Id.t -> Adoption.t list Lwt.t
end

module Make
    (Db : Forge.Db.S with type conn = Forge_db_mariadb.Client.t)
    (Cats : Cats_service.S) : S = struct
  module Sql = Shelter_sql.Make (Forge_db_mariadb.Sql)
  module Adoptions = Adoptions_crud.Make (Forge_db_mariadb.Sql)

  let adopt cat_id user_id =
    let user = Int64.of_int (User.Id.to_repr user_id) in
    Lwt_result.bind (Cats.adopt cat_id user_id) (fun () ->
        Db.with_conn @@ fun conn ->
        let%lwt inserted =
          Adoptions.insert conn
            ~cat_id:(Int64.of_int (Cat.Id.to_repr cat_id))
            ~user_id:user
        in
        let%lwt id = Inserted.id (module Adoption.Id) inserted in
        let%lwt adopted =
          Sql.List.adoptions_of conn ~user_id:user Adoption.of_row
        in
        Lwt.return
          (match List.length adopted with
          | 0 | 1 | 2 -> Ok { Adoption.id; cat_id; user_id }
          | _ -> Error (Forge.Error.conflict "a member adopts at most 2 cats")))

  let of_user user_id =
    Db.with_conn (fun conn ->
        Sql.List.adoptions_of conn
          ~user_id:(Int64.of_int (User.Id.to_repr user_id))
          Adoption.of_row)
end

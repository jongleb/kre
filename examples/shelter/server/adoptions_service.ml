module type S = sig
  val adopt : Cat.Id.t -> User.Id.t -> (Adoption.t, Forge.Error.t) result Lwt.t
  val of_user : User.Id.t -> Adoption.t list Lwt.t
end

module Make
    (Db : Forge.Db.S with type conn = Forge_db_mariadb.Client.t)
    (Cats : Cats_service.S)
    (Jobs : Forge.Job.S) : S = struct
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
          Adoptions.List.by_user_id conn ~user_id:user Adoption.of_row
        in
        match List.length adopted with
        | 0 | 1 | 2 ->
            let adoption = { Adoption.id; cat_id; user_id } in
            Lwt.map
              (fun () -> Ok adoption)
              (Jobs.enqueue Queues.congratulate adoption)
        | _ ->
            Lwt.return_error
              (Forge.Error.conflict "a member adopts at most 2 cats"))

  let of_user user_id =
    Db.with_conn (fun conn ->
        Adoptions.List.by_user_id conn
          ~user_id:(Int64.of_int (User.Id.to_repr user_id))
          Adoption.of_row)
end

module type S = sig
  val available : unit -> Cat.t list Lwt.t
  val find : Cat.Id.t -> Cat.t option Lwt.t
  val create : Create_cat_dto.t -> Cat.t Lwt.t
  val rename : Cat.Id.t -> Cat.Name.t -> (Cat.t, Forge.Error.t) result Lwt.t

  val adopt :
    conn:Forge_db_mariadb.Client.t ->
    Cat.Id.t ->
    User.Id.t ->
    (unit, Forge.Error.t) result Lwt.t
end

module Make (Db : Forge.Db.S with type conn = Forge_db_mariadb.Client.t) : S =
struct
  module Sql = Shelter_sql.Make (Forge_db_mariadb.Sql)
  module Cats = Cats_crud.Make (Forge_db_mariadb.Sql)

  let key id = Int64.of_int (Cat.Id.to_repr id)

  let available () =
    Db.with_conn (fun conn ->
        Sql.List.cats_with_status conn
          ~status:(Cat.Status.to_string Available)
          Cat.of_row)

  let find id =
    Db.with_conn (fun conn -> Cats.Single.find conn ~id:(key id) Cat.of_row)

  let create ({ name; age } : Create_cat_dto.t) =
    Db.with_conn (fun conn ->
        let%lwt inserted =
          Cats.insert conn ~name:(Cat.Name.to_repr name)
            ~age:(Int64.of_int (Cat.Age.to_repr age))
            ~status:(Cat.Status.to_string Available)
            ~owner_id:None
        in
        let%lwt id = Inserted.id (module Cat.Id) inserted in
        Lwt.return { Cat.id; name; age; status = Available; owner_id = None })

  let rename id name =
    Db.with_conn (fun conn ->
        let%lwt _ =
          Sql.rename_cat conn ~name:(Cat.Name.to_repr name) ~id:(key id)
        in
        Lwt.map
          (Option.to_result ~none:(Forge.Error.not_found "cat"))
          (Cats.Single.find conn ~id:(key id) Cat.of_row))

  let adopt ~conn id user =
    let%lwt changed =
      Sql.adopt_cat conn
        ~status:(Cat.Status.to_string Adopted)
        ~owner_id:(Some (Int64.of_int (User.Id.to_repr user)))
        ~id:(key id)
        ~available:(Cat.Status.to_string Available)
    in
    Lwt.return
      (match changed.affected_rows with
      | 1L -> Ok ()
      | _ -> Error (Forge.Error.conflict "this cat is not available"))
end

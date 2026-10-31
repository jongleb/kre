[@@@primary]

module Make (Db : Forge.Db.S with type conn = Forge_db_mariadb.Client.t) =
struct
  module Sql = Cats_sql.Make (Forge_db_mariadb.Sql)

  let reset () =
    Db.with_conn (fun conn ->
        let%lwt _ = Sql.drop conn in
        let%lwt _ = Sql.create_cats conn in
        Lwt.return_unit)

  let add (dto : Create_cat_dto.t) =
    Db.with_conn (fun conn ->
        let%lwt inserted =
          Sql.insert conn
            ~name:(Cat.Name.to_repr dto.name)
            ~age:(Int64.of_int (Cat.Age.to_repr dto.age))
            ~breed:(Cat.Breed.to_repr dto.breed)
        in
        Option.fold
          ~none:
            (Forge.Error.fail (Forge.Error.internal "insert returned no id"))
          ~some:(fun id ->
            Lwt.return
              {
                Cat.id = Int64.to_int id;
                name = dto.name;
                age = dto.age;
                breed = dto.breed;
              })
          inserted.insert_id)

  let find_all () =
    Db.with_conn (fun conn -> Sql.List.all conn ~limit:1000L Cat.of_row)

  let find id =
    Db.with_conn (fun conn ->
        Sql.Single.by_id conn ~id:(Int64.of_int id) Cat.of_row)
end

[@@@controller "batch"]

module Sql = Cats_sql.Make (Forge_db_mariadb.Sql)

let import (module Db : Forge.Db.S with type conn = Forge_db_mariadb.Client.t)
    ~(conn : (Forge_db_mariadb.Client.t[@from Db.tx]))
    ~(body : Create_cat_dto.t) : (unit, Forge.Error.t) result Lwt.t =
  let%lwt _ =
    Sql.insert conn
      ~name:(Cat.Name.to_repr body.name)
      ~age:(Int64.of_int (Cat.Age.to_repr body.age))
      ~breed:(Cat.Breed.to_repr body.breed)
  in
  match body.note with
  | "fail" -> Lwt.return_error (Forge.Error.conflict "import aborted")
  | _ -> Lwt.return_ok ()
[@@post] [@@transactional]

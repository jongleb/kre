# Data

Nest: TypeORM, Prisma, Mongoose — пять глав. Forge: одна цепочка, где схема — OCaml-тип, а каждый SQL-запрос проверяет компилятор.

1. `[@@deriving table]` на записи описывает таблицу (см. `Cat.t` в [Pipes](pipes.md)).
2. Маленький бинарь печатает `schema.sql`:

<!-- $MDX file=../examples/cats/db/schema.ml -->
```ocaml
let () = print_string (Forge.Table.schema [ Cat.table ])
```

3. sqlgg генерирует по `schema.sql` и запросам типизированный модуль (dune-правило в `examples/cats/db/dune`).
4. Сервис применяет его к traits драйвера и получает записи через `Cat.of_row`:

<!-- $MDX file=../examples/cats/db/cats_db_service.ml -->
```ocaml
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
        match
          Option.map
            (fun id -> Cat.Id.of_repr (Int64.to_int id))
            inserted.insert_id
        with
        | Some (Ok id) ->
            Lwt.return
              { Cat.id; name = dto.name; age = dto.age; breed = dto.breed }
        | Some (Error _) | None ->
            Forge.Error.fail
              (Forge.Error.internal "insert returned no valid id"))

  let find_all () =
    Db.with_conn (fun conn -> Sql.List.all conn ~limit:1000L Cat.of_row)

  let find id =
    Db.with_conn (fun conn ->
        Sql.Single.by_id conn ~id:(Int64.of_int (Cat.Id.to_repr id)) Cat.of_row)
end
```

Транзакция — `Db.transaction`: `Ok` → commit, `Error` или исключение → rollback. В контроллере — `[@@transactional]` и параметр `[@from Db.tx]`:

<!-- $MDX file=../examples/cats/db/batch_controller.ml -->
```ocaml
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
```
 Миграции — файлы `migrations/NNNN_name.sql` с секциями `-- migrate:up`/`-- migrate:down` и `forge migrate up|down|status|new`.

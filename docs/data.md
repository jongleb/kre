# Data

Nest: TypeORM, Prisma, Mongoose — five chapters. Kre: one chain, where the schema is an OCaml type and the compiler checks every SQL query.

1. `[@@deriving table]` on a record describes a table (see `Cat.t` in [Pipes](pipes.md)).
2. A small binary prints `schema.sql`:

<!-- $MDX file=../examples/cats/db/schema.ml -->
```ocaml
let () =
  print_string
    (match Sys.argv with
    | [| _; "crud" |] -> Kre.Table.crud Cat.table
    | [| _; "postgresql" |] -> Kre.Table.schema Postgresql [ Cat.table ]
    | _ -> Kre.Table.schema Mysql [ Cat.table ])
```

3. sqlgg generates a typed module from `schema.sql` and the queries (the dune rule is in `examples/cats/db/dune`).
4. The service applies it to the driver traits and gets records through `Cat.of_row`:

<!-- $MDX file=../examples/cats/db/cats_db_service.ml -->
```ocaml
[@@@primary]

module Make (Db : Kre.Db.S with type conn = Kre_db_mariadb.Client.t) = struct
  module Sql = Cats_sql.Make (Kre_db_mariadb.Sql)
  module Crud = Cats_crud.Make (Kre_db_mariadb.Sql)

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
            Kre.Error.fail (Kre.Error.internal "insert returned no valid id"))

  let find_all () = Db.with_conn (fun conn -> Crud.List.all conn Cat.of_row)

  let find id =
    Db.with_conn (fun conn ->
        Crud.Single.find conn ~id:(Int64.of_int (Cat.Id.to_repr id)) Cat.of_row)
end
```

CRUD without an ORM (the counterpart of `JpaRepository`): `schema.exe crud` prints, from `Cat.table`, the queries `all` and `insert`, plus `find`, `update` and `delete` when there is a primary key. sqlgg turns them into the module `Cats_crud`, and every query is still checked against the schema. The deriver provides `Cat.for_insert` and `Cat.for_update`: they spread a record into the named arguments of these queries, in the right order and with the right column types:

<!-- $MDX skip -->
```ocaml
let%lwt inserted = Cat.for_insert tom (Crud.insert conn) in
let%lwt _ = Cat.for_update { tom with name } (Crud.update conn) in
let%lwt _ = Crud.delete conn ~id in
```

Lookup by key is generated too, like derived queries in Spring Data (`findByStatus`) and `find_by` in Rails. A `[@unique]` column gets `by_<column>` returning one row (`Users_crud.Single.by_email`); `[@index]` and `[@references]` get a list ordered by the key (`Cats_crud.List.by_status`); every table gets `count`. Names come from the columns, not from parsing a method name, so a typo is a compile error, not a query error.

Custom queries (`JOIN`, filters) are written next to them in a plain `.sql` file, like `Cats_sql`.

## Time and versions

Rails: `t.timestamps` and `lock_version`. JPA: `@CreatedDate`, `@LastModifiedDate`, `@Version`. In Kre these are attributes on record fields:

<!-- $MDX skip -->
```ocaml
type t = {
  id : Id.t; [@primary] [@auto] [@column int]
  name : Name.t; [@column string] [@size 64]
  created_at : Kre_shared.Time.t; [@created_at]
  updated_at : Kre_shared.Time.t; [@updated_at]
  version : int; [@version]
}
[@@deriving table ~name:"notes", dto]
```

- `Kre_shared.Time.t` is a point in time: in JSON and URLs an RFC 3339 string (`"2026-11-01T06:44:08.112Z"`), in the database `DOUBLE` seconds. It works in Melange too.
- `for_insert` sets `created_at` and `updated_at` to the same `Kre.Table.now ()`, and `version` to 0. `for_update` updates `updated_at` and leaves `created_at` alone.
- With `[@version]`, the `update` query from `Table.crud` is `SET …, version = version + 1 WHERE id = @id AND version = @version`. The client sends the version it saw; if the record was changed in the meantime, 0 rows change and the service answers 409:

<!-- $MDX skip -->
```ocaml
let%lwt changed = Cat.for_update { cat with name; version } (Cats.update conn) in
match changed.affected_rows with
| 1L -> Lwt.return_ok { cat with name; version = version + 1 }
| _ -> Lwt.return_error (Kre.Error.conflict "the cat changed since you read it")
```

## Pages

Spring: `Pageable` and `Page<T>`. Rails: kaminari. In Kre a page request is `Kre_shared.Page.Request.t` (`?page=2&size=20`; page from 1, size from 1 to 100, otherwise 400), and the response is `'a Kre_shared.Page.t` with `items`, `page`, `size` and `total`. `Table.crud` prints `page` (`LIMIT @limit OFFSET @offset`) and `count`, and the service combines the two:

<!-- $MDX skip -->
```ocaml
let catalog request =
  Db.with_conn (fun conn ->
      let%lwt cats =
        Cats.List.page conn
          ~limit:(Int64.of_int request.Kre_shared.Page.Request.size)
          ~offset:(Int64.of_int (Kre_shared.Page.Request.offset request))
          Cat.of_row
      in
      let%lwt total = Cats.count conn in
      Lwt.return (Kre_shared.Page.make request ~total:(Int64.to_int total) cats))

let catalog (module Cats : Cats_service.S)
    ~(page : (Kre_shared.Page.Request.t[@search])) () :
    Cat.t Kre_shared.Page.t Lwt.t =
  Cats.catalog page
[@@get "catalog"]
```

The generated client is `Cats_client.catalog ~page`, with a response of the same type `Cat.t Kre_shared.Page.t`. The ppx serializes a response type `T.t M.t` through `M.Make (T)`, so a custom container (a cursor page, an envelope) is a module with `'a t` and `Make`.

A transaction is `Db.transaction`: `Ok` → commit, `Error` or an exception → rollback. As in Spring, the transaction's connection is bound to the current Lwt context: `Db.with_conn` and a nested `Db.transaction` inside it take the same connection, so services do not pass `~conn` to each other. A nested transaction is part of the outer one.

In a controller, `[@@transactional]` and a `Kre.Db.S` dependency are enough (example: `examples/shelter/server/adoptions_controller.ml`): all services the handler calls write into one transaction. When you need the `conn` itself, use a `[@from Db.tx]` parameter:

<!-- $MDX file=../examples/cats/db/batch_controller.ml -->
```ocaml
[@@@controller "batch"]

module Sql = Cats_sql.Make (Kre_db_mariadb.Sql)

let import (module Db : Kre.Db.S with type conn = Kre_db_mariadb.Client.t)
    ~(conn : (Kre_db_mariadb.Client.t[@from Db.tx])) ~(body : Create_cat_dto.t)
    : (unit, Kre.Error.t) result Lwt.t =
  let%lwt _ =
    Sql.insert conn
      ~name:(Cat.Name.to_repr body.name)
      ~age:(Int64.of_int (Cat.Age.to_repr body.age))
      ~breed:(Cat.Breed.to_repr body.breed)
  in
  match body.note with
  | "fail" -> Lwt.return_error (Kre.Error.conflict "import aborted")
  | _ -> Lwt.return_ok ()
[@@post] [@@transactional]
```
 Migrations are files `migrations/NNNN_name.sql` with `-- migrate:up`/`-- migrate:down` sections, plus `kre migrate up|down|status|new`.

## PostgreSQL

The driver is `kre-db-postgresql` (libpq). The service code stays the same; three things change:

- `Kre.Table.schema Postgresql [ Cat.table ]` prints DDL for Postgres: `SERIAL` for `[@primary] [@auto]`, `DOUBLE PRECISION`, a separate `CREATE INDEX`;
- sqlgg runs with `-dialect postgresql`, and SQL parameters become `$1, $2…`;
- the traits and the pool are `Kre_db_postgresql.Sql` and `Kre.Db.Make (Kre_db_postgresql.Driver)`.

The driver takes `insert_id` from `SELECT lastval()` on the same connection. So `Crud.insert` returns the id, as on MariaDB. `affected_rows` comes from the server response. Migrations, `[@@transactional]` and live loaders work the same way.

sqlgg limits for Postgres: no `RETURNING`, `BIGSERIAL` or `GENERATED … AS IDENTITY`, so the key is `SERIAL` (int4). libpq queries run in a thread pool (`Lwt_preemptive`), one per connection.

Example and test: `examples/cats/postgresql`: `KRE_TEST_PG_URL=postgresql://… dune build @examples/cats/postgresql/pg`.

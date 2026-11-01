# Data

Nest: TypeORM, Prisma, Mongoose — пять глав. Kre: одна цепочка, где схема — OCaml-тип, а каждый SQL-запрос проверяет компилятор.

1. `[@@deriving table]` на записи описывает таблицу (см. `Cat.t` в [Pipes](pipes.md)).
2. Маленький бинарь печатает `schema.sql`:

<!-- $MDX file=../examples/cats/db/schema.ml -->
```ocaml
let () =
  print_string
    (match Sys.argv with
    | [| _; "crud" |] -> Kre.Table.crud Cat.table
    | [| _; "postgresql" |] -> Kre.Table.schema Postgresql [ Cat.table ]
    | _ -> Kre.Table.schema Mysql [ Cat.table ])
```

3. sqlgg генерирует по `schema.sql` и запросам типизированный модуль (dune-правило в `examples/cats/db/dune`).
4. Сервис применяет его к traits драйвера и получает записи через `Cat.of_row`:

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

CRUD без ORM (аналог `JpaRepository`): `schema.exe crud` печатает по `Cat.table` запросы `all`, `insert`, а при первичном ключе ещё `find`, `update`, `delete`. sqlgg превращает их в модуль `Cats_crud`, и каждый запрос по-прежнему проверяется против схемы. Деривер даёт `Cat.for_insert` и `Cat.for_update`: они раскладывают запись в именованные аргументы этих запросов в нужном порядке и с нужными типами столбцов:

<!-- $MDX skip -->
```ocaml
let%lwt inserted = Cat.for_insert tom (Crud.insert conn) in
let%lwt _ = Cat.for_update { tom with name } (Crud.update conn) in
let%lwt _ = Crud.delete conn ~id in
```

Поиск по ключам тоже генерируется, как derived queries в Spring Data (`findByStatus`) и `find_by` в Rails. Для `[@unique]` столбца печатается `by_<столбец>` на одну строку (`Users_crud.Single.by_email`), для `[@index]` и `[@references]` — список по порядку ключа (`Cats_crud.List.by_status`), для любой таблицы — `count`. Имена берутся из столбцов, а не из разбора имени метода, поэтому опечатка — ошибка компиляции, а не запроса.

Свои запросы (`JOIN`, фильтры) пишутся рядом в обычном `.sql`, как `Cats_sql`.

## Время и версии

Rails: `t.timestamps` и `lock_version`. JPA: `@CreatedDate`, `@LastModifiedDate`, `@Version`. В Kre — атрибуты полей записи:

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

- `Kre_shared.Time.t` — момент времени: в JSON и URL строка RFC 3339 (`"2026-11-01T06:44:08.112Z"`), в базе `DOUBLE` секунд. Работает и в Melange.
- `for_insert` ставит `created_at` и `updated_at` в одно `Kre.Table.now ()`, `version` — в 0. `for_update` обновляет `updated_at`, `created_at` не трогает.
- С `[@version]` запрос `update` из `Table.crud` — `SET …, version = version + 1 WHERE id = @id AND version = @version`. Клиент присылает версию, которую видел; если запись успели изменить, строк изменится 0, и сервис отвечает 409:

<!-- $MDX skip -->
```ocaml
let%lwt changed = Cat.for_update { cat with name; version } (Cats.update conn) in
match changed.affected_rows with
| 1L -> Lwt.return_ok { cat with name; version = version + 1 }
| _ -> Lwt.return_error (Kre.Error.conflict "the cat changed since you read it")
```

## Страницы

Spring: `Pageable` и `Page<T>`. Rails: kaminari. В Kre запрос страницы — `Kre_shared.Page.Request.t` (`?page=2&size=20`; page от 1, size от 1 до 100, иначе 400), ответ — `'a Kre_shared.Page.t` с `items`, `page`, `size` и `total`. `Table.crud` печатает `page` (`LIMIT @limit OFFSET @offset`) и `count`, сервис складывает одно с другим:

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

Сгенерированный клиент — `Cats_client.catalog ~page`, ответ того же типа `Cat.t Kre_shared.Page.t`. Тип `T.t M.t` в ответе ppx сериализует через `M.Make (T)`, так что свой контейнер (курсорная страница, конверт) — модуль с `'a t` и `Make`.

Транзакция — `Db.transaction`: `Ok` → commit, `Error` или исключение → rollback. Как в Spring, соединение транзакции привязано к текущему Lwt-контексту: `Db.with_conn` и вложенный `Db.transaction` внутри неё берут его же, поэтому сервисы не передают `~conn` друг другу. Вложенная транзакция — часть внешней.

В контроллере хватает `[@@transactional]` и зависимости `Kre.Db.S` (пример — `examples/shelter/server/adoptions_controller.ml`): все сервисы, которые хендлер вызывает, пишут в одну транзакцию. Нужен сам `conn` — параметр `[@from Db.tx]`:

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
 Миграции — файлы `migrations/NNNN_name.sql` с секциями `-- migrate:up`/`-- migrate:down` и `kre migrate up|down|status|new`.

## PostgreSQL

Драйвер — `kre-db-postgresql` (libpq). Код сервиса тот же; меняются три вещи:

- `Kre.Table.schema Postgresql [ Cat.table ]` печатает DDL для Postgres: `SERIAL` для `[@primary] [@auto]`, `DOUBLE PRECISION`, отдельный `CREATE INDEX`;
- sqlgg запускается с `-dialect postgresql`, и параметры в SQL становятся `$1, $2…`;
- трейты и пул — `Kre_db_postgresql.Sql` и `Kre.Db.Make (Kre_db_postgresql.Driver)`.

`insert_id` драйвер берёт из `SELECT lastval()` на том же соединении. `Crud.insert` поэтому возвращает id, как на MariaDB. `affected_rows` берётся из ответа сервера. Миграции, `[@@transactional]` и live loaders работают так же.

Ограничения sqlgg для Postgres: нет `RETURNING`, `BIGSERIAL` и `GENERATED … AS IDENTITY`, поэтому ключ — `SERIAL` (int4). Запросы libpq идут в пуле потоков (`Lwt_preemptive`), по одному на соединение.

Пример и тест — `examples/cats/postgresql`: `KRE_TEST_PG_URL=postgresql://… dune build @examples/cats/postgresql/pg`.

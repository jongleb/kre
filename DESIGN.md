# Kre — дизайн NestJS-подобного фреймворка на OCaml

Oct 31, 2026 · @Mr

## Цель и принципы

Kre — фуллстек-фреймворк на OCaml, который воспроизводит структуру и главы [docs.nestjs.com](https://docs.nestjs.com/) средствами OCaml 5.5: сервер на Dream, фронтенд на Melange, общий код в `shared/`. Документация Kre повторяет оглавление Nest глава в главу; глава считается закрытой, когда её примеры из Nest переписаны на Kre и компилируются.

Принципы, которые решают спорные вопросы при разработке:

1. **Не воспроизводить то, что в OCaml уже есть; DI — при сборке, не в рантайме.** Проводку зависимостей делает ppx `[%wire]` (аналог `@ComponentScan` + `@Autowired`) по модулям и функторам: ошибки DI — ошибки компиляции. Рантайм-контейнера, токенов и рефлексии нет; ООП не используется — только модули, функторы и функции. Nest-овские `@Module`, DI-контейнер, `forwardRef`, Discovery, Module reference — это компенсация отсутствия модульной системы в TS. У нас модуль = singleton-провайдер, `.mli` = exports, `main.ml` = composition root, зависимости = module-dependent functions (modular explicits, OCaml 5.5). Разрешение зависимостей — на этапе компиляции, а не старта.
2. **ppx только там, где нужен рефлекшн.** Маршруты из сигнатур хендлеров, кодеки и валидация DTO, конфиг из env, типизированные пути на фронте. Всё остальное — обычные функции и модули.
3. **Dream не оборачиваем.** `Dream.request`, `Dream.middleware`, `Dream.response`, сессии, CSRF, websockets, static — используются напрямую. Kre добавляет слой выше, не прячет слой ниже.
4. **Контроллер — источник правды.** Из него (через `spec`) генерируются типизированный Melange-клиент и OpenAPI. Контракт нигде не дублируется руками.
5. **Один синтаксис для сервера и клиента.** Пользовательский код на обоих концах читается одинаково: атрибуты на `let`, `[@@deriving …]` на типах.
6. **Illegal states unrepresentable, минимум кода.** Никаких `assert false`, никаких `Obj.magic`, ошибки ppx — через `Location.raise_errorf` с текстом, объясняющим, что исправить.

Не делаем в первых фазах: ORM (вместо него sqlgg + `table`), GraphQL, microservices/transporters, queues, MongoDB, platform-agnosticism (только Dream), Devtools-граф, Observability-SaaS.

## Стек и версии

Сервер и клиент — OCaml 5.5.1 в одном opam-switch: Melange `7.0.1-55` собран под 5.5, modular explicits компилируются и в native, и в JS (проверено в фазе 0).

| Компонент | Версия / выбор | Зачем |
| --- | --- | --- |
| OCaml | 5.5.0 ([релиз 19 июня 2026](https://ocaml.org/changelog/2026-06-19-ocaml-550)) | modular explicits `(module M : S) -> …`, полиморфные параметры, GC |
| ppxlib | ≥ 0.38.0 (в switch — 0.39.0) | все ppx Kre |
| dune | ≥ 3.21 (в switch — 3.24) | `(modes :standard melange)` для shared, `melange.emit` |
| Dream | 1.0.0 | HTTP, sessions, CSRF, websocket, static |
| routes | 2.0.0 | типизированные пути на обоих концах |
| Lwt + lwt\_ppx | 6.1 | монада сервера; `let%lwt`, `match%lwt` |
| Melange | 7.0.1-55 (OCaml 5.5) | фронтенд, `Js.Promise` |
| reason-react + mlx | текущие | компоненты, JSX-синтаксис в `.mlx` |
| jsonkit | собственная | JSON-тип и `[@@deriving jsonschema]`, native + melange |
| sqlgg / ppx\_sqlgg | собственный форк | типизированный SQL |
| cmdliner | текущая | CLI `kre` |
| ocamlformat | 0.29 (синтаксис 5.5) | форматирование |
| cram (dune) + alcotest | текущие | тесты: ppx — cram на вывод `pp.exe`, остальное — alcotest |

**Два базовых решения по библиотекам.** Весь JSON — [jsonkit](https://github.com/melange-community/jsonkit): тип `Jsonkit.t`, кодеки, `[@@deriving jsonschema]`; Kre не определяет собственного JSON-типа и не генерирует кодеков сам — чего не хватает, добавляется в jsonkit. Все пути — [routes](https://github.com/anuragsoni/routes) (anuragsoni): типизированный двунаправленный роутер, чистый OCaml, работает и в Melange; одно значение `Routes.path` даёт матчинг на сервере, `sprintf` для клиентов и `string_of_path` для OpenAPI. `Dream.router` со строковыми паттернами не используется; `Kre.App.handler` матчит через `Routes.one_of`/`Routes.match'` и остаётся обычным `Dream.handler`.

**Правило про версии компилятора (решено в фазе 0).** Melange 7.0.1-55 поддерживает OCaml 5.5, поэтому отдельный switch для клиента не нужен, а синтаксис 5.5 (modular explicits) разрешён везде, включая `shared/` и `client/`. `dune-project` требует `ocaml >= 5.5 & < 5.6`; локальный switch проекта — `opam switch create . 5.5.1`.

**Монады.** Сервер — `Lwt.t`; клиент — `Js.Promise.t`. `Kre_client.Promise` даёт `return`, `let*`, `let+` над `Js.Promise.t` в Melange и над `Lwt.t` в native, поэтому код поверх клиента собирается в обоих режимах (типа-алиаса `Promise.t` нет). Ни один тип в `shared/` не упоминает монаду: контракт между концами — только данные (DTO) и `spec`.

**Lwt-конвенции.** Пользовательский код — `lwt_ppx` (`let%lwt`, `match%lwt`, `try%lwt`); сгенерированный ppx-код — `Lwt_result.Syntax` (`let*` над `('a, Error.t) result Lwt.t`), без `lwt_ppx`, чтобы `kre.ppx` не зависел от порядка применения препроцессоров. Исключения в хендлерах ловятся в `Kre.Route.handle` через `Lwt.catch`, не через `try%lwt` в сгенерированном коде. Жизненный цикл — `Lwt_switch` (`run ~on_shutdown` вешает на него). Таймаут на хендлер — `[@@timeout 5.0]` → `Lwt.pick` с `Lwt_unix.sleep`, по умолчанию выключен. Eio и `Lwt_eio` не используются; переход на effects — только вместе с заменой Dream, через тот же `Kre.Route.handle`.

**Многоядерность.** Dream однодоменный. Горизонтальное масштабирование — N процессов за балансировщиком; `Kre.App.run ~domains` не планируется.

## Структура репозитория и пакеты

Один монорепозиторий `kre`, четыре opam-пакета. Пример `examples/cats` — порт примера из Nest-доков и одновременно интеграционный тест.

```
kre/
  dune-project
  kre.opam          # kre.shared (Kre_shared, native + melange) и kre (Kre, рантайм сервера, native)
  kre-ppx.opam      # ppx: controller, dto, config, table
  kre-client.opam   # Kre_client: Http, Router, Path, Search + ppx search/params/path (melange)
  kre-cli.opam      # бинарь kre
  src/
    shared/           # Kre_shared: Validation, Codec, Json, Refined — собирается в обоих режимах
    core/             # Kre: Error, Response, Guard, Spec, Route, Controller, App
    ppx/              # один драйвер, несколько трансформаций (см. раздел ppx)
    client/           # melange-библиотека
    cli/              # cmdliner
  examples/cats/
    dune-project
    shared/           # Cat, Create_cat_dto  (modes :standard melange)
    server/           # Cats_service, Cats_controller, Config, Db
    client/           # Routes, Cats_page.mlx, gen/cats_client.ml (генерируется)
    bin/main.ml
  test/
    ppx/              # cram-тесты на вывод драйвера: эталон каждой трансформации + каждая ошибка
    core/             # alcotest: Error.handler, Codec, Validation, Spec→OpenAPI
    e2e/              # поднимает examples/cats, дёргает Dream.test и сгенерированный клиент
  docs/               # зеркало оглавления docs.nestjs.com, по файлу на главу
```

Правила зависимостей между пакетами:

- `kre.shared` зависит только от jsonkit (native) / jsonkit-melange (melange); Dream и Lwt не видит.
- `kre` зависит от `kre.shared`, Dream, Lwt, routes, jsonkit; не зависит от ppx.
- `kre-ppx` зависит от ppxlib и jsonkit (для `dto`); генерируемый код ссылается только на `Kre.*`, `Kre_shared.*` и `Jsonkit.*`.
- `kre-client` зависит от melange, reason-react, jsonkit-melange, `kre.shared`; не зависит от `kre`.
- `shared/` пользовательского проекта зависит только от jsonkit и `kre.shared` (+ `kre-ppx` для `dto`), собирается в обоих режимах.

Модульные имена: `Kre_shared` (общие для обоих концов: `Kre_shared.Refined`, `Kre_shared.Codec`, …), `Kre` (сервер: `Kre.Error`, `Kre.App`, …), `Kre_client`, `Kre_ppx` (не экспортируется пользователю). Разделение — решение фазы 0: `shared/` собирается в Melange и не может зависеть от серверной библиотеки, которая тянет Dream. Ре-экспорт `Kre_shared` из `Kre` не делается (правило «никаких алиасов»).

## Сквозной пример: cats

Этот код — критерий приёмки фазы 1: он должен компилироваться и работать end-to-end. Это порт `CatsController` / `CatsService` / `CreateCatDto` из Nest-доков.

**shared/cat.ml** — тип ответа, виден обоим концам:

```ocaml
type t = { id : int; name : string; age : int; breed : string }
[@@deriving dto]
(* генерирует: of_json, to_json, jsonschema *)
```

**shared/create\_cat\_dto.ml** — тело запроса. Ограничения живут в opaque-типах полей, а не в атрибутах: невалидное значение `Name.t` не существует.

```ocaml
module Name  = Kre_shared.Refined.String (struct let name = "name"  let min = 1 let max = 64 end)
module Age   = Kre_shared.Refined.Int    (struct let name = "age"   let min = 0 let max = 40 end)
module Breed = Kre_shared.Refined.Enum   (struct let name = "breed" let values = [ "siamese"; "persian"; "maine coon" ] end)

type t = { name : Name.t; age : Age.t; breed : Breed.t }
[@@deriving dto]
(* генерирует: of_json, to_json, jsonschema, validate (здесь — identity) *)

(* escape hatch для разового правила без своего типа: *)
type quick = { nickname : string [@validate max_length 16] } [@@deriving dto]
```

**server/cats\_service.ml** — провайдер. Модуль = singleton, состояние внутри (`private readonly cats: Cat[] = []`):

```ocaml
module type S = sig
  val add      : Create_cat_dto.t -> Cat.t Lwt.t
  val find_all : unit -> Cat.t list Lwt.t
  val find     : int -> Cat.t option Lwt.t
end

let cats : Cat.t Dynarray.t = Dynarray.create ()

let add (d : Create_cat_dto.t) =
  let c = { Cat.id = Dynarray.length cats + 1; name = d.name; age = d.age; breed = d.breed } in
  Dynarray.add_last cats c;
  Lwt.return c

let find_all () = Lwt.return (Dynarray.to_list cats)
let find id = Lwt.return (Dynarray.find_opt (fun c -> c.Cat.id = id) cats)
```

**server/cats\_controller.ml** — контроллер. Модульные параметры хендлеров = зависимости (modular explicits):

```ocaml
[@@@controller "cats"]
[@@@use [ Logger_middleware.use ]]

open Kre

let find_all (module Cats : Cats_service.S) ?(limit : int = 20) () : Cat.t list Lwt.t =
  let%lwt all = Cats.find_all () in
  Lwt.return (List.filteri (fun i _ -> i < limit) all)
[@@get]

let find_one (module Cats : Cats_service.S) ~(id : int) : (Cat.t, Error.t) result Lwt.t =
  let%lwt c = Cats.find id in
  Lwt.return (Option.to_result c ~none:(Error.not_found "cat"))
[@@get ":id"]

let create (module Cats : Cats_service.S)
    ~(user : User.t [@guard Auth.current]) ~(body : Create_cat_dto.t) : Cat.t Lwt.t =
  Cats.add body
[@@post] [@@status 201]
```

**server/logger\_middleware.ml** — middleware как в Nest, но это просто `Dream.middleware`:

```ocaml
let use : Dream.middleware = fun next req ->
  Dream.log "Request...";
  next req
```

**bin/main.ml** — composition root; это и есть `AppModule`:

```ocaml
let () =
  let config = Config.load_exn () in
  Kre.App.run ~port:config.port
    ~middleware:[ Dream.logger ]
    [ Cats_controller.register (module Cats_service) ]
```

**client/gen/cats\_client.ml** — генерируется командой `kre client` из `spec` сервера:

```ocaml
val find_all : ?limit:int -> unit -> (Cat.t list, Kre_client.Error.t) result Promise.t
val find_one : id:int -> (Cat.t, Kre_client.Error.t) result Promise.t
val create   : body:Create_cat_dto.t -> (Cat.t, Kre_client.Error.t) result Promise.t
(* параметр user с [@guard] в клиент не попадает *)
```

**client/routes.ml** — typed router:

```ocaml
open Kre_client.Router

let root = root ~layout:App_layout.v

module Cats = struct
  type search = { limit : int [@default 20] } [@@deriving search]

  let index =
    child root ~path:[%path "/cats"] ~search:search_codec
      ~loader:(fun () s -> Cats_client.find_all ~limit:s.limit ())
      ~component:Cats_page.index

  type params = { id : int } [@@deriving params]

  let show =
    child index ~path:[%path "/:id"] ~params:params_codec
      ~loader:(fun { id } () -> Cats_client.find_one ~id)
      ~component:Cats_page.show
end

let router = make [ Cats.index; Cats.show ]
```

**client/cats\_page.mlx** — компонент; `Link` с неверными `params` не компилируется:

```ocaml
let show ~data ~params:_ ~search:_ =
  match data with
  | Error e -> <Error_box error=e />
  | Ok cat ->
    <div>
      <h1>(React.string cat.Cat.name)</h1>
      <Link route=Routes.Cats.index params=() search={ limit = 20 }>"back"</Link>
    </div>
```

## Пример приложения целиком: shelter

Приют для котов: пользователи, коты, усыновления. Задействовано всё из документа: opaque-типы, `table` + sqlgg, modular explicits, guards, `[@@authorize]`, `[@@transactional]`, live loaders, routes, typed router на фронте, Actuator. Это второй интеграционный пример (`examples/shelter`), критерий приёмки фазы 2.

```
shelter/
  shared/   user.ml  cat.ml  adoption.ml  login_dto.ml  session.ml
            create_cat_dto.ml  rename_dto.ml  adopt_dto.ml      (+ melange/ — те же файлы)
  schema/   credential.ml  schema.ml                            (таблица только сервера; печать DDL/CRUD)
  server/   config.ml  settings.ml  database.ml  inserted.ml  auth.ml
            users_service.ml  cats_service.ml  adoptions_service.ml
            auth_controller.ml  cats_controller.ml  adoptions_controller.ml
            sql/queries.sql  migrations/0001_init.sql
  client/   pages.mlx  routes.mlx  scenario.mlx                 (*_client.ml генерирует kre client)
  bin/      main.ml                                             (let app = [%wire])
  test/     test_shelter.ml  run_scenario.ml
```

**Как сделано (фаза 2)** — отличия от наброска ниже, каждое с причиной:

- Вход — JWT (`Kre.Jwt`), не cookie-сессия: `fetch` в node не хранит cookies, а e2e идёт из node. Токен несёт `User.t` в claims, поэтому `Auth.current` — `Guard.check` без запроса в БД и без middleware; `Auth.admin` даёт доказательство `Auth.Admin.t`.
- Пароли — отдельная таблица `credentials` (`schema/credential.ml`, PBKDF2-SHA256 из `kdf`, сравнение `Eqaf`), а не `password_hash` в `User.t`: тип, который уходит клиенту, не содержит хеша вовсе. `Credential.verify` возвращает `User.Id.t` как доказательство.
- `role`, `status` — варианты с `[@@deriving dto]`, которые стали скалярами (см. «Варианты» в dto); `Ptime`-полей нет — у `table` нет типа времени.
- Миграция `0001_init.sql` — это вывод `schema.exe migration`; правило `diff` в `server/sql/dune` роняет `dune test`, если таблицу поменяли без миграции.
- `Kre.Db.conn` общего нет: сервисы берут `Kre.Db.S with type conn = Kre_db_mariadb.Client.t`. `~conn` в сервисах тоже нет: `Cats.adopt` и `Adoptions.adopt` зовут `Db.with_conn` и попадают в транзакцию хендлера.
- `[@@transactional]` проверен откатом: третье усыновление уже обновило кота, лимит «2 на участника» возвращает `Error` — кот снова доступен, live-событий нет.
- `Config.interface` (по умолчанию `127.0.0.1`): Dream слушает `localhost`, который на macOS — `::1`.
- Тесты: `test_shelter` (alcotest через `Dream.test` и `[%wire]`, MariaDB) и `run_scenario` (запускает `bin/main.exe` и сценарий Melange-клиента в node: регистрация, 403, усыновление, 409, live `cats`, разметка страницы входа). Alias `@examples/shelter/test/shelter`, база — `KRE_TEST_SHELTER_URL`; в CI — job `db`.

Ниже — исходный набросок; код примера — в `examples/shelter`.

### shared — типы, одни на оба конца

```ocaml
(* user.ml *)
module Email = Kre_shared.Refined.Email
type role = Admin | Member [@@deriving dto]
type t = {
  id    : int;     [@primary] [@auto]
  email : Email.t; [@unique]
  role  : role;    [@default Member]
} [@@deriving table ~name:"users", dto]
(* table под melange ничего не эмитит; dto — и там, и там *)

(* cat.ml *)
module Name = Kre_shared.Refined.String (struct let name = "name" let min = 1 let max = 64 end)
module Age  = Kre_shared.Refined.Int    (struct let name = "age"  let min = 0 let max = 40 end)
type status = Available | Adopted [@@deriving dto]
type t = {
  id       : int;        [@primary] [@auto]
  name     : Name.t;
  age      : Age.t;
  status   : status;     [@default Available] [@index]
  owner_id : int option; [@references User]
} [@@deriving table ~name:"cats", dto]

(* adoption.ml *)
type t = {
  id         : int;     [@primary] [@auto]
  cat_id     : int;     [@references Cat]
  user_id    : int;     [@references User]
  adopted_at : Ptime.t; [@default "CURRENT_TIMESTAMP"]
} [@@deriving table ~name:"adoptions", dto]

(* login_dto.ml *)
type t = { email : User.Email.t; password : string [@validate min_length 8] } [@@deriving dto]
(* create_cat_dto.ml *)
type t = { name : Cat.Name.t; age : Cat.Age.t } [@@deriving dto]
(* adopt_dto.ml *)
type t = { cat_id : int } [@@deriving dto]
```

### server — конфиг, auth, сервисы

```ocaml
(* config.ml *)
type t = {
  port           : int;    [@env "PORT"] [@default 8080]
  db_url         : string; [@env "DATABASE_URL"]
  session_secret : string; [@env "SESSION_SECRET"] [@secret]
  env            : string; [@env "KRE_ENV"] [@default "dev"]
} [@@deriving config]
```

```sql
-- queries/cats.sql  (sqlgg; типы против schema.sql, который собрал [@@deriving table])
-- @available
SELECT id, name, age, status, owner_id FROM cats WHERE status = 'available' ORDER BY id;
-- @by_id
SELECT id, name, age, status, owner_id FROM cats WHERE id = @id;
-- @adopt
UPDATE cats SET status = 'adopted', owner_id = @user_id WHERE id = @id AND status = 'available';

-- queries/users.sql
-- @by_email
SELECT id, email, role, password_hash FROM users WHERE email = @email;
```

```ocaml
(* users_service.ml *)
module type S = sig
  val find   : int -> User.t option Lwt.t
  val verify : email:User.Email.t -> password:string -> User.t option Lwt.t
end
module Make (Db : Kre.Db.S) : S = struct
  let find id = Db.with_conn (fun c -> Users_sql.by_id c ~id >|= Option.map User.of_row)
  let verify ~email ~password =
    Db.with_conn (fun c ->
      let%lwt row = Users_sql.by_email c ~email:(User.Email.to_repr email) in
      Lwt.return (Option.bind row (fun r -> if Argon2.verify r.password_hash password then Some (User.of_row r) else None)))
end

(* cats_service.ml — Kre.Db.conn один для всех драйверов, поэтому сигнатура не зависит от Db *)
module type S = sig
  val available : unit -> Cat.t list Lwt.t
  val find      : int -> Cat.t option Lwt.t
  val create    : Create_cat_dto.t -> Cat.t Lwt.t
  val owner_of  : int -> int option Lwt.t
  val adopt     : conn:Kre.Db.conn -> cat:int -> user:int -> (unit, Kre.Error.t) result Lwt.t
end
module Make (Db : Kre.Db.S) : S = struct
  let available () = Db.with_conn (fun c -> Cats_sql.available c >|= List.map Cat.of_row)
  let find id = Db.with_conn (fun c -> Cats_sql.by_id c ~id >|= Option.map Cat.of_row)
  let create (d : Create_cat_dto.t) =
    Db.with_conn (fun c -> Cat.insert c { Cat.id = 0; name = d.name; age = d.age; status = Available; owner_id = None })
  let owner_of id = find id >|= Option.bind ~f:(fun c -> c.Cat.owner_id)
  let adopt ~conn ~cat ~user =
    let%lwt n = Cats_sql.adopt conn ~id:cat ~user_id:user in
    Lwt.return (if n = 1 then Ok () else Error (Kre.Error.conflict "cat is not available"))
end

(* adoptions_service.ml — зависимость от другого сервиса = функторный параметр *)
module type S = sig
  val adopt : conn:Kre.Db.conn -> cat:int -> user:int -> (Adoption.t, Kre.Error.t) result Lwt.t
end
module Make (Cats : Cats_service.S) : S = struct
  let adopt ~conn ~cat ~user =
    let open Lwt_result.Syntax in
    let* () = Cats.adopt ~conn ~cat ~user in
    let%lwt id = Adoption.insert conn { Adoption.id = 0; cat_id = cat; user_id = user; adopted_at = Ptime_clock.now () } in
    Lwt.return_ok { Adoption.id; cat_id = cat; user_id = user; adopted_at = Ptime_clock.now () }
end

(* auth.ml *)
let user_field : User.t Dream.field = Dream.new_field ~name:"user" ()

let session (module Users : Users_service.S) : Dream.middleware = fun next req ->
  (match Dream.session_field req "uid" with
   | Some id -> Users.find (int_of_string id) >|= Option.iter (Dream.set_field req user_field)
   | None -> Lwt.return_unit) >>= fun () -> next req

let current : User.t Kre.Guard.t = Kre.Guard.field user_field ~missing:(Kre.Error.unauthorized "login required")
let admin   : unit Kre.Guard.t   = fun req ->
  current req >|= Result.bind ~f:(fun u -> if u.User.role = Admin then Ok () else Error (Kre.Error.forbidden "admin only"))
```

### server — контроллеры

```ocaml
(* auth_controller.ml *)
[@@@controller "auth"]

let login (module Users : Users_service.S) (req : Dream.request) ~(body : Login_dto.t)
    : (User.t, Kre.Error.t) result Lwt.t =
  match%lwt Users.verify ~email:body.email ~password:body.password with
  | None -> Lwt.return_error (Kre.Error.unauthorized "bad credentials")
  | Some u -> let%lwt () = Dream.set_session_field req "uid" (string_of_int u.id) in Lwt.return_ok u
[@@post "login"]

let me ~(user : User.t [@guard Auth.current]) () : User.t Lwt.t = Lwt.return user
[@@get "me"]

let logout (req : Dream.request) () : unit Lwt.t = Dream.invalidate_session req
[@@post "logout"]

(* cats_controller.ml *)
[@@@controller "cats"]

let index (module Cats : Cats_service.S) () : Cat.t list Lwt.t = Cats.available ()
[@@get] [@@live ["cats"]]            (* фронт перезапросит при изменении cats *)

let show (module Cats : Cats_service.S) ~(id : int) : (Cat.t, Kre.Error.t) result Lwt.t =
  Cats.find id >|= Option.to_result ~none:(Kre.Error.not_found "cat")
[@@get ":id"]

let create (module Cats : Cats_service.S) ~(body : Create_cat_dto.t) : Cat.t Lwt.t = Cats.create body
[@@post] [@@status 201] [@@guards [Auth.admin]]

let rename (module Cats : Cats_service.S)
    ~(user : User.t [@guard Auth.current]) ~(id : int) ~(body : Create_cat_dto.t)
    : (Cat.t, Kre.Error.t) result Lwt.t = …
[@@put ":id"]
[@@authorize fun ~user ~id -> Cats.owner_of id >|= fun o -> user.role = Admin || o = Some user.id]

(* adoptions_controller.ml *)
[@@@controller "adoptions"]

let adopt (module Adoptions : Adoptions_service.S)
    ~(user : User.t [@guard Auth.current])
    ~(conn : Kre.Db.conn [@from Kre.Db.tx])
    ~(body : Adopt_dto.t) : (Adoption.t, Kre.Error.t) result Lwt.t =
  Adoptions.adopt ~conn ~cat:body.cat_id ~user:user.id
[@@post] [@@status 201] [@@transactional]
(* Error → rollback + 409; Ok → commit + Live.publish "cats" и "adoptions" (из writes sqlgg/table) *)
```

### bin/main.ml — весь composition root

```ocaml
let () =
  let config = Config.load_exn () in
  let module Db = Kre.Db.Make (Kre_db_mariadb) (struct let url = config.db_url let pool = 8 end) in
  let module Users = Users_service.Make (Db) in
  let module Cats = Cats_service.Make (Db) in
  let module Adoptions = Adoptions_service.Make (Cats) in
  Kre.App.run ~port:config.port
    ~middleware:[ Dream.logger; Dream.cookie_sessions ~secret:config.session_secret; Auth.session (module Users) ]
    [ Auth_controller.register (module Users);
      Cats_controller.register (module Cats);
      Adoptions_controller.register (module Adoptions);
      Kre.Actuator.routes ~config:(Config.pp config) () ]
```

Забыли `(module Users)` — не компилируется. Переименовали `Cat.name` — не компилируются `cats.sql` (через `schema.sql`), `Create_cat_dto`, клиент, страницы.

### client

```ocaml
(* routes.ml *)
open Kre_client.Router
let root = root ~layout:Layout.v ()

module Cats = struct
  let index = child root ~path:[%path "/cats"] ~live:true
      ~loader:(fun () () -> Cats_client.index ())
      ~component:Cats_index.v

  type params = { id : int } [@@deriving params]
  let show = child root ~path:[%path "/cats/:id"]
      ~loader:(fun { id } () -> Cats_client.show ~id)
      ~component:Cat_show.v
end

let login = child root ~path:[%path "/login"] ~component:Login.v
let router = make [ Any Cats.index; Any Cats.show; Any login ]
```

```ocaml
(* pages/cat_show.mlx *)
let v ~data ~params:_ ~search:_ =
  let adopt cat_id () =
    Adoptions_client.adopt ~body:{ Adopt_dto.cat_id }
    |> Promise.iter (function
         | Ok _ -> Router.navigate Routes.Cats.index ~params:() ~search:()
         | Error e -> Toast.error (Kre_client.Error.message e))
  in
  match data with
  | Error e -> <Error_box error=e />
  | Ok (cat : Cat.t) ->
    <div>
      <h1>(React.string (Cat.Name.to_repr cat.name))</h1>
      <p>(React.string (Printf.sprintf "%d years" (Cat.Age.to_repr cat.age)))</p>
      (match cat.status with
       | Available -> <button onClick=(fun _ -> adopt cat.id ())>"Adopt"</button>
       | Adopted   -> <span>"already adopted"</span>)
      <Link route=Routes.Cats.index params=() search=()>"back"</Link>
    </div>
```

Страница `/cats` подписана на `cats`: пока один пользователь смотрит список, другой усыновляет — список обновляется без кода подписки. Ошибка 409 из `[@@transactional]` приходит в `Toast.error` как Problem Details.

## Kre.Core — рантайм сервера

Сигнатуры ниже — `.mli` из `src/shared` и `src/core` в том виде, в каком они собраны в фазе 0; ppx генерирует код только против них. Всё, чего здесь нет, в рантайм не попадает без правки этого раздела.

### Kre\_shared — общий для сервера и клиента (native + melange)

```ocaml
(* Kre_shared.Validation — ошибки и правила; Nest: class-validator *)
module Validation : sig
  type error = { path : string list; rule : string; message : string }
  type t = private { first : error; rest : error list }   (* непустой набор *)
  exception Invalid of t                (* бросают jsonkit-декодеры; Json.parse ловит *)
  type 'a rule
  val fail : rule:string -> string -> t
  val ok_exn : ('a, t) result -> 'a
  val to_list : t -> error list
  val to_json : t -> Jsonkit.t
  val rule : name:string -> ('a -> ('a, string) result) -> 'a rule
  val check : 'a rule list -> 'a -> ('a, t) result   (* все упавшие правила, не fail-fast *)
  val field : string -> 'a rule list -> 'a -> ('a, t) result   (* check + путь [name] *)
  module Syntax : sig   (* аппликативно: and+ накапливает ошибки обеих сторон *)
    val ( let+ ) : ('a, t) result -> ('a -> 'b) -> ('b, t) result
    val ( and+ ) : ('a, t) result -> ('b, t) result -> ('a * 'b, t) result
  end
  val min_length : int -> string rule   val max_length : int -> string rule
  val min : int -> int rule             val max : int -> int rule
  val range : min:int -> max:int -> int rule
  val one_of : string list -> string rule
  val email : string rule
end

(* Kre_shared.Asset и Icon — фаза 3: значения, которые дают только [%asset] и [%icon] *)
module Asset : sig
  type t
  val checked : string -> t        (* для ppx *)
  val url : t -> string
end
module Icon : sig
  type t
  val checked : name:string -> string -> t   (* для ppx *)
  val name : t -> string
  val svg : t -> string
end

(* Kre_shared.Time — фаза 3: момент времени UTC; RFC 3339 в JSON и URL, секунды в базе *)
module Time : sig
  type t
  include Scalar.S with type t := t
  val of_seconds : float -> t
  val to_seconds : t -> float
  val compare : t -> t -> int
end

(* Kre_shared.Page — фаза 3: страница списка; Spring Page *)
module Page : sig
  type 'a t = private { items : 'a list; page : int; size : int; total : int }
  module Request : sig
    type t = private { page : int; size : int }
    include Json.S with type t := t
    val make : page:int -> size:int -> (t, Validation.t) result
    val first : t
    val offset : t -> int
    val codec : t Search.t
  end
  val make : Request.t -> total:int -> 'a list -> 'a t
  val pages : 'a t -> int
  module Make (J : Json.S) : Json.S with type t = J.t t
end

(* Kre_shared.Search — фаза 3: кодек query-строки ↔ запись; [@@deriving search] *)
module Search : sig
  type 's t
  type ('a, 'b) presence = Required : ('a, 'a) presence | Optional : ('a, 'a option) presence
                        | Default : 'a -> ('a, 'a) presence | Repeated : ('a, 'a list) presence
  type 'a field
  val none : unit t
  val field : string -> (module S : Scalar.S) -> (S.t, 'b) presence -> 'b field
  val read : 'a field -> (string * string) list -> ('a, Validation.t) result
  val show : 'a field -> 'a -> (string * string) list
  val make : parse:((string * string) list -> ('s, Validation.t) result) -> print:('s -> (string * string) list list) -> 's t
  val decode : 's t -> (string * string) list -> ('s, Validation.t) result
  val encode : 's t -> 's -> (string * string) list
end

(* Kre_shared.Json — форма, которую даёт [@@deriving json, jsonschema] из jsonkit *)
module Json : sig
  module type S = sig
    type t
    val of_json : Jsonkit.t -> t          (* jsonkit-конвенция: бросает *)
    val to_json : t -> Jsonkit.t
    val t_jsonschema : Jsonkit.Jsonschema.t
  end
  val parse : (module J : S) -> Jsonkit.t -> (J.t, Validation.t) result
  module List (J : S) : S with type t = J.t list
end

(* Kre_shared.Scalar — значение, которое живёт и в JSON, и в сегменте пути/query; Nest: ParseIntPipe *)
module Scalar : sig
  module type S = sig
    type t
    include Json.S with type t := t
    val name : string                     (* "int", "string", … — в Spec *)
    val of_string : string -> (t, Validation.t) result
    val to_string : t -> string
  end
  module Int : S with type t = int        module Int64 : S with type t = int64
  module Float : S with type t = float    module Bool : S with type t = bool
  module String : S with type t = string
end
```

`Kre_shared.Refined` — см. раздел dto.

### Kre — сервер (native)

```ocaml
(* Kre.Error — единый тип ошибок; Nest: HttpException + exception filters *)
module Error : sig
  type status = [ Dream.client_error | Dream.server_error | `Unprocessable_Entity ]
  type t = private {
    status : status; code : string; type_ : string; detail : string;
    extensions : (string * Jsonkit.t) list;   (* доп. члены Problem Details верхнего уровня *)
  }
  exception E of t
  type handler = Dream.request -> t -> Dream.response Lwt.t   (* exception filter *)
  val make : status:status -> code:string -> ?type_:string -> ?extensions:(string * Jsonkit.t) list -> string -> t
  val bad_request : ?extensions:(string * Jsonkit.t) list -> string -> t   (* 400 *)
  val unauthorized : string -> t      (* 401 *)
  val forbidden : string -> t         (* 403 *)
  val not_found : string -> t         (* 404 *)
  val conflict : string -> t          (* 409 *)
  val unprocessable : Kre_shared.Validation.t -> t   (* 422, extensions.errors *)
  val internal : string -> t          (* 500 *)
  val to_json : instance:string -> t -> Jsonkit.t      (* RFC 9457 *)
  val to_response : Dream.request -> t -> Dream.response Lwt.t
  val fail : t -> 'a Lwt.t
end

(* Kre.Response — явный JSON-ответ; остальное (text, html, redirect, stream) — сам Dream *)
module Response : sig
  val json : ?status:Dream.status -> (module J : Kre_shared.Json.S) -> J.t -> Dream.response Lwt.t
end

(* Kre.Guard — извлечение значения из запроса; Nest: guards + custom param decorators *)
module Guard : sig
  type 'a t = Dream.request -> ('a, Error.t) result Lwt.t
  val field : 'a Dream.field -> missing:Error.t -> 'a t
  val header : string -> string t
  val both : 'a t -> 'b t -> ('a * 'b) t
  val session : string -> string t                     (* поле сессии, иначе 401 *)
  val map : ('a -> 'b) -> 'a t -> 'b t
  val check : ('a -> ('b, Error.t) result) -> 'a t -> 'b t   (* роль → доказательство *)
  val optional : 'a t -> 'a option t
end

(* Kre.Spec — рантайм-описание контроллера; источник для kre client / kre openapi *)
module Spec : sig
  type verb = [ `GET | `POST | `PUT | `PATCH | `DELETE ]
  type presence = Required | Optional | Repeated
  type location = Path | Query of presence | Header of presence | Cookie of presence
                | Search                       (* фаза 3: вся query-строка в запись, [@search] *)
  type dto = { name : string; schema : Jsonkit.Jsonschema.t }
  type param = { name : string; location : location; scalar : string; schema : Jsonkit.Jsonschema.t }
  type returns = Unit | Text | Json of value | Events of value | Raw
  type route = {
    verb : verb; path : string; name : string; params : param list;
    body : dto option; returns : returns; status : Dream.status; guards : string list;
    live : string list;                          (* [@@live], фаза 2 *)
  }
  type t = { prefix : string; version : int option; routes : route list }
  val to_json : t -> Jsonkit.t
end

(* Kre.Route — то, во что ppx превращает хендлер; логика здесь, не в сгенерированном коде *)
module Route : sig
  type handler = Dream.request -> (Dream.response, Error.t) result Lwt.t
  type t = private { verb : Spec.verb; middleware : Dream.middleware list; target : handler Routes.route }
  type 'a returns =
    | Unit : unit returns
    | Text : string returns
    | Json : (module Kre_shared.Json.S with type t = 'a) -> 'a returns
    | Found : (module Kre_shared.Json.S with type t = 'a) -> 'a option returns   (* None → 404 *)
    | Raw : Dream.response returns
    | Redirect : string -> unit returns                                              (* Location *)
  val v : ?middleware:Dream.middleware list -> Spec.verb -> handler Routes.route -> t
  val handle : status:Dream.status -> ?guards:unit Guard.t list -> ?headers:(string * string) list -> ?timeout:float -> 'a returns ->
    (Dream.request -> ('a, Error.t) result Lwt.t) -> handler
  val events : status:Dream.status -> ?guards:unit Guard.t list -> ?headers:(string * string) list ->
    (module J : Kre_shared.Json.S) -> (Dream.request -> (J.t Lwt_stream.t, Error.t) result Lwt.t) -> handler   (* [@@sse] *)
end

(* Kre.Controller *)
module Controller : sig
  type t = private { spec : Spec.t; middleware : Dream.middleware list; routes : Route.t list; error_handler : Error.handler option }
  val v : ?middleware:Dream.middleware list -> ?error_handler:Error.handler -> spec:Spec.t -> Route.t list -> t
end

(* Kre.App — сборка и запуск *)
module App : sig
  type tls = Development_certificate | Certificate of { certificate_file : string; key_file : string }
  val handler : ?middleware:Dream.middleware list -> ?error_handler:Error.handler -> Controller.t list -> Dream.handler
  val run : ?interface:string -> ?port:int -> ?tls:tls -> ?middleware:Dream.middleware list ->
    ?error_handler:Error.handler -> ?on_start:(unit -> unit Lwt.t) -> ?on_shutdown:(unit -> unit Lwt.t) ->
    ?commands:Command.t list -> Controller.t list -> unit   (* argv: команда → выполнить её; иначе сервер *)
end

(* Kre.Etag — фаза 3: ETag из тела ответа 200 на GET/HEAD, If-None-Match → 304; [@@etag] *)
module Etag : sig
  val middleware : Dream.middleware
end

(* Kre.Retry — фаза 3: повтор при исключении, пауза удваивается; [@@retry n] [@@backoff s] *)
module Retry : sig
  val run : ?backoff:float -> attempts:int -> (unit -> 'a Lwt.t) -> 'a Lwt.t
end

(* Kre.Command — фаза 3: команды бинаря; [@@command "…"] генерирует, [%wire] собирает, App.run ~commands запускает *)
module Command : sig
  type t
  type args = (string * string) list
  type invocation = Serve | Usage of string | Run of (unit -> unit Lwt.t) | Invalid of string
  val make : name:string -> doc:string -> options:string list ->
    (args -> (unit -> unit Lwt.t, Kre_shared.Validation.t) result) -> t
  val required : (module S : Kre_shared.Scalar.S) -> string -> args -> (S.t, Kre_shared.Validation.t) result
  val optional : (module S : Kre_shared.Scalar.S) -> string -> default:S.t -> args -> (S.t, Kre_shared.Validation.t) result
  val invoke : t list -> string list -> invocation
end

(* Kre.Job — фаза 3: очереди в БД; [@@job q] регистрирует обработчик, воркер — хуки провайдера *)
module Job : sig
  type 'a queue
  type handler
  val queue : string -> (module Kre_shared.Json.S with type t = 'a) -> 'a queue
  val handle : 'a queue -> ('a -> (unit, string) result Lwt.t) -> handler
  val table : Table.t
  module type S = sig
    val enqueue : ?delay:float -> 'a queue -> 'a -> unit Lwt.t
    val register : handler -> unit
    val drain : unit -> int Lwt.t
    val on_start : unit -> unit Lwt.t
    val on_shutdown : unit -> unit Lwt.t
  end
  module Make (Db : Db.S) (Config : sig val poll : float val attempts : int end) : S
end

(* Kre.Profiler — фаза 3: запросы и их SQL в dev; /__kre/profiler *)
module Profiler : sig
  type entry = { method_ : string; target : string; status : int; milliseconds : float; queries : string list }
  val sql : string -> unit                 (* драйверы *)
  val middleware : Dream.middleware
  val controller : Controller.t
  val recent : unit -> entry list
  val repeated : entry -> (string * int) list   (* N+1 *)
end

(* Kre.Mail — фаза 3: письма; провайдеры Smtp и Outbox *)
module Mail : sig
  type t = private { from : Kre_shared.Refined.Email.t; to_ : Kre_shared.Refined.Email.t;
                     cc : Kre_shared.Refined.Email.t list; subject : string; text : string; html : string option }
  val make : from:Kre_shared.Refined.Email.t -> to_:Kre_shared.Refined.Email.t ->
    ?cc:Kre_shared.Refined.Email.t list -> subject:string -> text:string -> ?html:string -> unit -> t
  val render : t -> string
  module type S = sig val send : t -> (unit, string) result Lwt.t end
  module Smtp (Config : sig val host : string val port : int val helo : string end) : S
  module Outbox () : sig include S val sent : unit -> t list val controller : Controller.t end
end

(* Kre.Assets — фаза 3: /assets/<имя>.<хеш>.<расширение> с вечным кэшем; ссылки даёт [%asset] *)
module Assets : sig
  val middleware : dir:string -> Dream.middleware
end

(* Kre.Live — live loaders, фаза 2 *)
module Live : sig
  val publish : string list -> unit                        (* хранилища без SQL *)
  val read : string -> unit                                (* драйвер: SELECT, для проверки [@@live] *)
  val wrote : string -> unit                               (* драйвер: INSERT/UPDATE/DELETE *)
  val deferred : (unit -> ('a, 'e) result Lwt.t) -> ('a, 'e) result Lwt.t   (* Db.transaction *)
  val audit : string list -> Dream.middleware              (* ppx для [@@live] *)
  val subscribe : string list -> string Lwt_stream.t * (unit -> unit)
  val controller : Controller.t                            (* GET /__kre/live?table=… *)
end
```

Отклонения от первой версии этого раздела (фаза 0) и почему:

- `Kre.run`/`Kre.app` → `Kre.App.run`/`Kre.App.handler`: обёрточный модуль dune не может содержать значения без ре-экспорта подмодулей алиасами, а алиасы запрещены.
- `Codec.t` (запись) → модули `Kre_shared.Scalar.S`: одна сущность «значение в JSON и в URL», `Refined.Make` собирается через `include` без алиасов, а ppx передаёт `(module Kre_shared.Scalar.Int)` как modular explicit.
- `Json.DTO` с `validate` убран: проверка — часть `of_json` (parse, don't validate). Все ошибки разбора тела — `Validation.t`; невалидный JSON-текст — 400, ошибки полей и типов — 422.
- `Error.t`: статус ограничен 4xx/5xx, `details : Jsonkit.t option` → `extensions` (Problem Details раскладывает их на верхний уровень, поэтому это объект, а не любое значение); `Response.t` (алиас `Dream.response`) и обёртки над `Dream.html`/`redirect`/`stream` убраны — принцип «Dream не оборачиваем».
- `Spec.param.required : bool` → `location = Path | Query of presence`; `?tls:bool` → вариант `tls`.
- `error_handler` получает запрос: Problem Details требует `instance`.
- `Validation.regex` и `Refined.Regex` отложены: регулярки нужны в обоих режимах, а `Str` есть только в native (см. открытые вопросы).

Поведение `App`: каждый маршрут — `Route.t` с методом; `App.handler` собирает по `Routes.one_of` на метод и матчит путь из `Dream.target` без query. `MatchWithTrailingSlash` → 301 на путь без слеша с тем же query. Нет маршрута → `error_handler` с `Error.not_found`. Все ответы-ошибки идут через `error_handler` (по умолчанию `Error.to_response`); `Error.E` из хендлера → его статус; прочие исключения → 500 `internal` и лог. Порядок: глобальные middleware → матчинг → контроллерные (`[@@@use]`) → хендлерные (`[@@use]`) → guards → парсинг параметров → тело хендлера (Nest Request lifecycle). `App.run` вызывает `on_start`, затем `Dream.serve` до SIGINT/SIGTERM, затем `on_shutdown`.

## ppx: controller

Одна глобальная трансформация ppxlib (`Driver.register_transformation ~impl`) по всему structure файла. Она работает чисто синтаксически: типов она не видит, поэтому всё, что нужно для генерации, берётся из аннотаций. Правило: **хендлер без аннотации типа возврата — ошибка компиляции.**

### Атрибуты

| Атрибут | Где | Payload | Nest-аналог |
| --- | --- | --- | --- |
| `[@@@controller "cats"]` | первый item файла | строка-префикс; `""` допустимо | `@Controller('cats')` |
| `[@@@version 2]` | floating | int → префикс `/v2` (режим URI) | `@Controller({ version: '2' })` |
| `[@@@use [m1; m2]]` | floating | `Dream.middleware list` | `MiddlewareConsumer.forRoutes` |
| `[@@@guards [g1; g2]]` | floating | `unit Guard.t list` — проверяют, значение отбрасывают | `@UseGuards` на классе |
| `[@@@inject: module X : S]` | floating | зависимость, доступная всему файлу (для хелперов) | constructor injection |
| `[@@get ""]` `[@@post]` `[@@put ":id"]` `[@@patch]` `[@@delete]` | на `let` | строка-путь относительно префикса; пустая/отсутствующая = `""` | `@Get(':id')` |
| `[@@status 201]` | на `let` | int | `@HttpCode(201)` |
| `[@@use [...]]`, `[@@guards [...]]` | на `let` | как floating, но для одного хендлера | `@UseGuards` на методе |
| `[@@header ("Cache-Control", "no-store")]` | на `let` | пара строк, повторяемый | `@Header()` |
| `[@@redirect "/x"]` | на `let` | строка (+ опц. status) | `@Redirect` |
| `[@@sse]` | на `let` | нет; возврат `τ Lwt_stream.t` | `@Sse` |
| `[@guard e]` / `[@from e]` | на параметре | `e : 'a Guard.t`; синонимы | `@UseGuards` + custom param decorator |

### Форма хендлера

```ocaml
let name (module M1 : S1) … (module Mn : Sn)   (* 0..n модульных параметров — зависимости *)
    ~p1 ?p2 ?(p3 = default) …                   (* labelled/optional — path/query/body/guard *)
    (req : Dream.request)?                        (* опциональный позиционный *)
    ()                                            (* обязателен, если нет других позиционных *)
    : <return-type> = body
[@@verb path] [@@…]
```

### Классификация параметров

В порядке проверки:

1. Label встречается как `:label` в полном пути (префикс + путь хендлера) → **path**. Тип обязателен в аннотации.
2. Label = `body` → **body**. Тип `T.t` (или список) → модуль `T : Kre_shared.Json.S`; генерируется `Kre.Route.body (module T)`: не-JSON → 400, ошибки разбора и правил → 422.
3. Параметр несёт `[@guard e]`/`[@from e]` → **guard**: `e req` вычисляется до тела; `Error` → ответ; в `spec` и в клиент не попадает.
4. Всё остальное labelled/optional → **query**, тип обязателен. `?(x : τ option)` и `~(x : τ option)` = необязательный; `?(x : τ = d)` = необязательный с дефолтом (дефолт применяет сам хендлер, ppx передаёт `?x`); `~(x : τ)` = обязательный, отсутствие → 400; `~(x : τ list)` → повторяемый `?x=a&x=b`.
5. Позиционный с аннотацией `Dream.request` → сырой запрос. Любой другой позиционный, кроме финального `()`, — ошибка.

Подбор модуля по типу (синтаксически): `int → Kre_shared.Scalar.Int`, `int64`, `float`, `bool`, `string` — аналогично; `T.t → T` (для path/query `T : Kre_shared.Scalar.S`, для body и результата `T : Kre_shared.Json.S`); `τ list` в body/результате → `Kre_shared.Json.List (τ)`. Иной тип → ошибка с перечислением форм. `[@codec e]` не реализован: свой разбор — это свой модуль `Scalar.S` (например, `Refined.Make`).

### Инъекция из запроса: `[@from]` и `Kre.Extract`

Все параметр-декораторы Nest (`@Req`, `@Res`, `@Headers`, `@Ip`, `@Session`, `@HostParam`, `@Query()` целиком, `createParamDecorator`) — это один механизм: параметр с `[@from e]`, где `e : 'a Guard.t = Dream.request -> ('a, Error.t) result Lwt.t`. Параметр может быть labelled (`~ip:(string [@from Extract.ip])`) или **позиционным** (`(ip : string [@from Extract.ip])`) — Nest-стиль; это уточняет правило 5 выше: позиционный параметр либо `Dream.request`, либо `()`, либо несёт `[@from]`.

ppx для хендлера с n такими параметрами генерирует n последовательных `let*` в обёртке — арность статическая, тип каждого извлечения проверяется компилятором против аннотации. Порядок извлечения — слева направо; первая `Error` прерывает цепочку.

```ocaml
let find_all (module Cats : Cats_service.S)
    (req : Dream.request)                                  (* @Req() *)
    (ip : string [@from Extract.ip])                       (* @Ip() *)
    (ua : string option [@from Extract.header "user-agent"])  (* @Headers('user-agent') *)
    (sess : Session.t [@from Auth.session])                (* @Session() / свой декоратор *)
    () : Cat.t list Lwt.t = …
[@@get]
```

`Kre.Extract` — стандартные извлечения, в `Core`:

```ocaml
module Extract : sig
  val req     : Dream.request Guard.t
  val ip      : string Guard.t
  val host    : string Guard.t
  val header  : string -> string option Guard.t           (* None, если нет *)
  val header_exn : string -> string Guard.t               (* 400, если нет *)
  val headers : (string * string) list Guard.t
  val cookie  : string -> string option Guard.t
  val query   : (string * string) list Guard.t            (* @Query() целиком *)
  val search  : 's Kre_shared.Search.t -> 's Guard.t    (* фаза 3: @Query() dto, [@search] *)
  val params  : (string * string) list Guard.t            (* @Param() целиком *)
  val body_raw : string Guard.t
  val body_json : Jsonkit.t Guard.t                       (* @Body() без DTO *)
  val session : string -> string option Guard.t           (* Dream.session_field *)
  val field   : 'a Dream.field -> missing:Error.t -> 'a Guard.t
end
```

Свой декоратор (`createParamDecorator`) — обычное значение: `let tenant : Tenant.t Guard.t = fun req -> …`. Комбинаторы в `Guard`: `map`, `both`, `optional : 'a t -> 'a option t`, `with_default`. `@Res()` аналога нет намеренно: ответ — возвращаемое значение, а для полного контроля есть `Response.t Lwt.t`.

### Тип возврата

Распознаваемые формы аннотации (`τ` — тип данных, `E` = `Kre.Error.t`):

| Аннотация | Сериализация | `Spec.returns` |
| --- | --- | --- |
| `unit Lwt.t` | пустой ответ, статус по умолчанию 204 | `Unit` |
| `string Lwt.t` | `text/plain` | `Text` |
| `T.t Lwt.t` | `T.to_json`, `application/json` | `Json ("T", T.jsonschema)` |
| `T.t list Lwt.t`, `T.t option Lwt.t` | JSON-массив / JSON или 404 | `Json` с обёрткой в схеме |
| `T.t M.t Lwt.t` (фаза 3) | контейнер `M.Make (T)`, например `Cat.t Kre_shared.Page.t` → `Kre_shared.Page.Make (Cat)`; свой контейнер — модуль с `'a t` и `Make (J : Json.S)` | `Json` |
| `(τ, E) result Lwt.t` | как τ; `Error e` → `error_handler` | как τ |
| `Dream.response Lwt.t` | как есть | `Raw` |
| `T.t Lwt_stream.t Lwt.t` + `[@@sse]` | `text/event-stream`, по событию `data: <json>` на элемент (`Kre.Route.events`) | `Events` |

Не-`Lwt` возврат — ошибка «handler must return … Lwt.t». Аннотация, не подпадающая под таблицу, — ошибка с перечислением форм.

### Зависимости (modular explicits)

Модульные параметры всех хендлеров объединяются по имени. Одно имя с разными сигнатурами — ошибка. Объединённый список становится параметрами `register` в порядке первого появления. Хендлеры остаются как написаны, со своими modular explicits; `register` вызывает их как `find_one (module Cats) ~id`. Функтор `Make` из первой версии плана не нужен (решение фазы 1): так меньше переписывания, хендлер можно вызвать в тесте напрямую, а `[@@@inject]` для хелперов отложен.

### Что генерируется

Файл остаётся как был (атрибуты Kre снимаются), в конец добавляются три элемента. Для `cats` с хендлером `find_one (module Cats : Cats_service.S) ~(id : int)`:

```ocaml
module Paths = struct
  let find_one () =
    Routes.(/?) (Routes.(/) (Routes.s "cats")
                   (Kre.Route.segment (module Kre_shared.Scalar.Int) ":id")) Routes.nil
end

let spec : Kre.Spec.t = { Kre.Spec.prefix = "/cats"; version = None; routes = [ … ] }

let register (module Cats : Cats_service.S) =
  Kre.Controller.v ~middleware:[ Logger_middleware.use ] ~spec
    [ Kre.Route.v `GET
        (Routes.(@-->) (Paths.find_one ())
           (fun __kre_arg_id ->
              Kre.Route.handle ~status:(Dream.int_to_status 200)
                (Kre.Route.Json (module Cat))
                (fun __kre_request -> find_one (module Cats) ~id:__kre_arg_id))) ]
```

Извлечения (query, body, `[@guard]`/`[@from]`) идут цепочкой `let open Kre.Route.Syntax in let* … in`, слева направо; первая `Error` прерывает цепочку. Хендлер без зависимостей даёт `register ()`. Функции `Paths` принимают `()`, чтобы путь был полиморфным: `Routes.sprintf (Cats_controller.Paths.find_one ()) 42 = "/cats/42"`. Путь сегмента — `Kre.Route.segment (module M) ":name"`: отказ `M.of_string` — это `NoMatch`, то есть 404. Полные эталоны вывода — `test/ppx/controller.t`.

`Kre.Route` — модуль рантайма: `handle` оборачивает guards, сериализацию и маппинг ошибок; `query`, `body`, `segment`, `ok`, `Syntax.let*` — всё, что вызывает сгенерированный код. Логики в сгенерированном коде нет.

Фаза 2: `[@@header (k, v)]` (повторяемый, на успешный ответ), `[@@redirect "/url"]` (хендлер с `unit Lwt.t`, статус по умолчанию 302), `[@@timeout 5.0]` (`Lwt.pick` со сном, по истечении — 504 `timeout`), `[@@@error_handler h]` (`Kre.Error.handler` для ошибок маршрутов этого контроллера) — сделаны, пример — `docs/examples/legacy_controller.ml`. `[@@@inject]` не нужен: хелпер принимает модуль параметром, как хендлер. `[@codec e]` не нужен: свой разбор — свой модуль `Scalar.S`. `[@@sse]` — отдельной строкой.

### Ошибки ppx (все через `Location.raise_errorf`, с локацией на виновный узел)

- `[@@@controller]` не первый item; два `[@@@controller]` в файле.
- `[@@get]` на `let` с паттерном не-идентификатором, на `let rec`, на `and`.
- Отсутствие аннотации типа возврата; неподдерживаемая форма.
- Path-параметр из пути без соответствующего label (`":id"`, но нет `~id`), и наоборот — label совпадает с `:x`, но тип не аннотирован.
- Два параметра `body`; `body` без типа `T.t`.
- Позиционный параметр без аннотации `Dream.request`.
- Конфликт сигнатур модульного параметра.
- `[@@status]` вне 100–599; `[@@sse]` без `Lwt_stream.t`.

Каждая ошибка — отдельный случай в cram-тесте `test/ppx/errors.t` (вывод `pp.exe -impl`).

## DI и остальные примитивы Nest

Все примитивы Overview-раздела Nest выражаются без контейнера. Таблица ниже — нормативная: так, и только так, переводится каждая концепция.

| Nest | Kre | Механизм |
| --- | --- | --- |
| Provider (`@Injectable`, singleton) | модуль с `module type S` в `.mli` | состояние — top-level значения модуля |
| Provider с зависимостями | функтор `Make (Db : Db.S) (Log : Logger.S) : S` | применяется в `main.ml` |
| Constructor injection | модульные параметры хендлера `(module Cats : Cats_service.S)` | modular explicits → параметры `register` |
| `useValue` / `useClass` / `useFactory` | другой модуль того же `S`; фабрика = `let%lwt` в `main` до `Kre.App.run` | — |
| Dynamic module `forRoot(cfg)` | функтор с конфиг-модулем: `Cache.Make (struct let ttl = 60 end)` | — |
| Scope.DEFAULT | модуль | — |
| Scope.REQUEST | `Dream.field` + `Guard.field` | значение кладёт middleware, читает `[@guard]` |
| Scope.TRANSIENT | обычная функция | — |
| `@Module({imports, providers, exports})` | `main.ml` + `.mli` + dune `(libraries)` | не существует как сущность |
| Circular dependency / `forwardRef` | ошибка компиляции | — |
| Middleware | `Dream.middleware`; `[@@@use]` / `[@@use]` / `Kre.App.run ~middleware` | — |
| Middleware с зависимостями | `let use (module Log : Logger.S) : Dream.middleware = …` | применяется в `[@@@use [Logger.use (module Log)]]` |
| Guard (`canActivate`) | `'a Guard.t = Dream.request -> ('a, Error.t) result Lwt.t` | `[@guard e]` даёт значение; `[@@guards [e]]` только проверяет |
| Pipe (`ParseIntPipe`) | аннотация типа параметра | `Codec` |
| Pipe (`ValidationPipe`) | `[@@deriving dto]` → `validate` | автоматически на `body` |
| Custom pipe | `[@codec e]` на параметре / `Codec.custom` | — |
| Interceptor (before/after) | `Dream.middleware` | — |
| Interceptor (transform response) | middleware над `Dream.response` или явный `Response.json` | RxJS не вводим |
| Exception filter | `Kre.App.run ~error_handler`; на контроллер — `[@@@error_handler f]` | `Error.t -> Dream.response Lwt.t` |
| `HttpException` | `Error.t` в `result` или `Error.fail` | — |
| Custom param decorator (`@User()`) | `[@from Auth.current]` | любой `'a Guard.t` |
| Execution context | позиционный `(req : Dream.request)` | — |
| Lifecycle (`onModuleInit`, `onApplicationShutdown`) | `Kre.App.run ~on_start ~on_shutdown` | `Lwt_switch` внутри |

### Проводка: `[%wire]` (фаза 2)

```ocaml
(* bin/main.ml *)
let () =
  let app = [%wire] in
  Kre.App.run ~on_start:app.on_start ~on_shutdown:app.on_shutdown app.controllers
```

Как `@SpringBootApplication`, `[%wire]` сканирует каталог приложения — родитель каталога с `main.ml` — рекурсивно, пропуская `test`/`tests`, `_build`, `node_modules` и скрытые; копии одного модуля (`copy_files#` для Melange) склеиваются по имени. Сузить — `[%wire "server"; "db"]`, пути от каталога приложения. В dune: `(preprocessor_deps (source_tree ..))` — пересборка при изменении исходников. Компоненты ppx находит сам:

| Что в файле | Роль | Nest / Spring |
| --- | --- | --- |
| `module Make () = …` | провайдер; новый экземпляр | `@Injectable`, `@Scope(PROTOTYPE)` при ручном вызове |
| `module Make (Db : Kre.Db.S) (Clock : Clock.S) = …` | провайдер с зависимостями; параметры — constructor injection | `@Autowired` в конструкторе |
| `module type S` без `Make` | синглтон: модуль сам и есть экземпляр | `@Service` |
| `[@@@controller]` | потребитель: модульные параметры хендлеров → `register` | `@Controller` |
| остальное | не трогается | — |

Интерфейс провайдера — аннотация результата `Make` в `.ml` или `.mli` (`: Cats_service.S`, `: sig include Kre.Db.S … end`), иначе собственный `module type S`; явно — `[@@@injectable Iface.S]`. Модуль только с `module type S` (без значений и без `Make`) — интерфейс, а не провайдер. `[@@@fallback]` — запасной провайдер (`@ConditionalOnMissingBean`, аналог `@Optional`): используется и создаётся, только если других реализаций интерфейса нет. Если интерфейс дают несколько провайдеров: `[@@@primary]` (`@Primary`), иначе имя параметра функтора, совпадающее с именем провайдера (`(Fake_clock : Clock.S)` — как Spring берёт бин по имени параметра), иначе ошибка сборки. Ошибки сборки с местом: нет провайдера, неоднозначность, цикл (`Clock -> Report -> Clock`). Типы зависимостей проверяет компилятор на сгенерированных применениях функторов.

Хуки: `let on_start` / `let on_shutdown` в провайдере (и в его сигнатуре) — `@PostConstruct` / `@PreDestroy`, `onModuleInit` / `onApplicationShutdown`; запуск — в порядке зависимостей, остановка — в обратном. `[%wire]` возвращает `Kre.Wiring.t = { controllers; on_start; on_shutdown; health; commands; beans }`; `beans` — граф для `/actuator/beans`. Модули каталогов должны быть видны из `main` (библиотеки `(wrapped false)`). Эталоны — `test/wire/wire.t`; пример — `examples/cats/bin/main.ml` (`Settings` → `Database.Make` → `Cats_db_service.Make`).

### Guards — пример

```ocaml
(* server/auth.ml *)
let user_field : User.t Dream.field = Dream.new_field ~name:"user" ()

(* middleware кладёт пользователя в запрос по сессии/JWT *)
let session (module Users : Users_service.S) : Dream.middleware = fun next req ->
  (match Dream.session_field req "user_id" with
   | None -> Lwt.return_unit
   | Some id ->
     let%lwt u = Users.find (int_of_string id) in
     Option.iter (Dream.set_field req user_field) u;
     Lwt.return_unit)
  >>= fun () -> next req

(* guard читает его *)
let current : User.t Guard.t = Guard.field user_field ~missing:(Error.unauthorized "login required")

let role r : unit Guard.t = fun req ->
  let%lwt u = current req in
  Lwt.return (Result.bind u (fun u -> if List.mem r u.User.roles then Ok () else Error (Error.forbidden "role")))
```

Использование: `~(user : User.t [@guard Auth.current])` в параметрах, ``[@@guards [Auth.role `Admin]]`` на хендлере. Порядок: `[@@@guards]` → `[@@guards]` → `[@guard]`-параметры слева направо.

### Request-scoped провайдеры

Никакого «bubbling» скоупов: request-scoped значение — это `Dream.field`, который заполняет middleware. Сервис, которому нужно request-значение, получает его аргументом функции, не конструктора. Это сознательное отклонение от Nest: оно убирает целую главу (Injection scopes) и класс ошибок производительности.

## ppx: \[@@deriving dto\]

Deriver на записях, вариантах и алиасах; работает в native и melange (стдлиб ≥ 4.12, без `Js`, без yojson — те же ограничения, что у jsonkit). Покрывает главы Validation, Serialization и часть OpenAPI (Types and parameters, Mapped types).

Генерирует для `type t` модуль формы `Kre_shared.Json.S` (решение фазы 0, см. «Связь с jsonkit»):

```ocaml
val of_json      : Jsonkit.t -> t      (* jsonkit [@@deriving json] + правила; бросает Validation.Invalid *)
val to_json      : t -> Jsonkit.t      (* jsonkit [@@deriving json] *)
val t_jsonschema : Jsonkit.Jsonschema.t   (* jsonkit [@@deriving jsonschema] + ограничения *)
```

На границе (тело запроса, ответ клиента) вызывается `Kre_shared.Json.parse (module T) json : (T.t, Validation.t) result`. Отдельного `validate` нет: проверка — часть разбора, и после `of_json` значение уже валидно.

Для `type foo` — те же имена с префиксом `foo_` (конвенция jsonkit: `foo_of_json`, `foo_jsonschema`).

### Рекомендуемый путь: opaque-типы (parse, don't validate)

Поле DTO должно иметь тип, в котором невалидное значение непредставимо. Тогда `of_json` — единственная точка проверки, а сервис никогда не получает «сырую» строку. `[@validate]` на `string`/`int` — допустимый escape hatch для одноразовых правил, но не основной способ.

`Kre_shared.Refined` — фабрики opaque-типов, собранные в `shared/` (реализовано в фазе 0):

```ocaml
module type S = sig
  type t
  type repr
  include Kre_shared.Scalar.S with type t := t   (* of_json/to_json/t_jsonschema + of_string/to_string: работает и в теле, и в path/query *)
  val of_repr : repr -> (t, Kre_shared.Validation.t) result   (* умный конструктор *)
  val to_repr : t -> repr
  val pp : Format.formatter -> t -> unit
end

module type RULES = sig
  type base
  val name : string                                         (* title в схеме *)
  val rules : base Kre_shared.Validation.rule list
  val constraints : (string * Jsonkit.Jsonschema.t) list    (* minLength, enum, format, … *)
end

module Make (Base : Kre_shared.Scalar.S) (C : RULES with type base := Base.t) : S with type repr = Base.t
module String (C : sig val name : string  val min : int  val max : int end) : S with type repr = string
module Int    (C : sig val name : string  val min : int  val max : int end) : S with type repr = int
module Enum   (C : sig val name : string  val values : string list end)    : S with type repr = string
module Email  : S with type repr = string
(* Regex — отложен: нужен regex-движок, работающий и в native, и в melange *)
```

Связь с `dto`: поле типа `T.t`, где `T : Json.S`, кодируется через `T.of_json`/`T.to_json`, схема — `T.t_jsonschema`. Это ровно то, что вызывает деривер jsonkit для поля типа `T.t`, поэтому opaque-модули из `Refined` встраиваются в jsonkit-записи без участия ppx. Ошибки полей должны собираться аппликативно (не fail-fast) в один `Validation.t` с путями — для этого jsonkit-декодеру нужен режим с накоплением ошибок и путями (открытый вопрос; до него — первая ошибка, путь пустой).

Кросс-полевые инварианты (пароль = подтверждение, `from < to`) — либо opaque-запись со своим `of_repr`, либо `[@@dto.check f]` на типе, `f : t -> (t, Validation.t) result`, который `of_json` вызывает последним.

### Идентификаторы: `Kre_shared.Id` (фаза 2)

```ocaml
module Id = Kre_shared.Id.Make ()          (* в cat.ml: свой тип на каждую сущность *)
type t = { id : Id.t; [@primary] [@auto] [@column int] … } [@@deriving table ~name:"cats", dto]
let find_one (module Cats : Cats_service.S) ~(id : Cat.Id.t) : … [@@get ":id"]
```

`Id.Make ()` — генеративный функтор: id кота не подставить вместо id владельца. `Id.S` — это `Refined.S` над `int` (`of_repr` пропускает только `≥ 1`) плюс `first`, `succ`, `equal`: значение дают разбор (JSON, путь, query, строка из базы) или `succ`, сервису в памяти не нужна проверка, которая может упасть. Так как `Id.S` — `Scalar.S` и `Json.S`, id работает в пути (`/cats/0` → 404 до хендлера), в теле, в `spec`, в `table` и в клиентском роутере. Шаблон `kre generate controller` создаёт ресурс с `Id`.

### typegist — решение фазы 0: (б), не используется

[typegist](https://github.com/dbuenzli/typegist) представляет OCaml-типы как значения, поверх которых пишутся generic-кодеки. Решение — (б): `dto` не генерирует gist, а опирается на деривера jsonkit. Причины: в opam есть только `typegist.0.0.0`; принято, что весь JSON — jsonkit, а в jsonkit уже есть `[@@deriving json]` и `[@@deriving jsonschema]` на обоих бэкендах, так что `dto` сводится к тонкой надстройке (правила, `[@exclude]`, `[@expose]`), и gist дублировал бы jsonkit. Вернуться к вопросу, если понадобятся generic-производные, которых нет в jsonkit (QuickCheck-генераторы, диффы).

### Как устроен dto (фаза 1)

`dto` — преобразование препроцессинга (`Driver.register_transformation ~preprocess_impl ~preprocess_intf`), оно отрабатывает до дериверов. `[@@deriving dto]` переписывается в `[@@deriving json, jsonschema]` из jsonkit; `~strict` добавляет `[@@disallow_extra_fields]`. Атрибуты полей не переименовываются: ppxlib сопоставляет атрибут по суффиксу имени, поэтому `[@key]` и `[@default]` видят оба деривера jsonkit (`json.key` и `jsonschema.key`). Если у полей есть `[@validate]`, после типа добавляется обёртка, которая перекрывает `of_json` из jsonkit:

```ocaml
let of_json __kre_json =
  let __kre_value = of_json __kre_json in
  Kre_shared.Validation.ok_exn
    (let open Kre_shared.Validation.Syntax in
     let+ __kre_name = Kre_shared.Validation.field "fullName" [ Kre_shared.Validation.(max_length 8) ] __kre_value.name
     and+ __kre_tag = … in
     { __kre_value with name = __kre_name; tag = __kre_tag })
```

`and+` накапливает ошибки всех полей, путь — JSON-ключ поля. Для полей примитивных типов в области видимости должен быть `open Jsonkit.Primitives` (требование jsonkit). Пользовательский `shared/` подключает `(pps jsonkit.ppx kre-ppx)` в native и `(pps melange.ppx jsonkit-melange.ppx kre-ppx)` в melange. Эталоны — `test/ppx/dto.t`.

### Атрибуты полей

| Атрибут | Эффект | Nest-аналог |
| --- | --- | --- |
| `[@key "camelName"]` | имя в JSON (jsonkit `json.key`/`jsonschema.key`) | `@Expose({ name })` |
| `[@default e]` | поле необязательно в JSON, дефолт при отсутствии (jsonkit) | `@IsOptional` + default |
| `[@validate r1; r2]` | правила `'a Kre_shared.Validation.rule`, применяются по порядку, ошибки всех правил собираются | class-validator |
| `[@validate.custom f]` | `f : t_field -> (t_field, string) result` → `Validation.rule ~name:"custom" f` | `@Validate(Custom)` |
| `[@exclude]` | не сериализуется в `to_json`; `of_json` требует `[@default]` — фаза 2 | `@Exclude` |
| `[@expose ~groups:["admin"]]` | сериализуется только при `to_json ~groups` — фаза 2 | `@Expose({ groups })` |
| `[@nested]` | не нужен: вложенный DTO проверяется своим `T.of_json` | `@ValidateNested` |

Правила валидации — обычные значения `Kre_shared.Validation.*`; ppx лишь вызывает их и собирает `{ path; rule; message }`. Новые правила добавляются в рантайм, а не в ppx.

### Опции деривера

| Опция | Эффект | Nest-аналог |
| --- | --- | --- |
| `[@@deriving dto]` | всё выше | — |
| `[@@deriving dto ~partial_of:T]` | тип = все поля `T.t` как `option`; `validate` применяет правила `T` к присутствующим полям | `PartialType` |
| `[@@deriving dto ~pick_of:(T, ["name"; "age"])]` / `~omit_of` | подмножество полей `T` | `PickType` / `OmitType` |
| `[@@deriving dto ~strict]` | неизвестные поля в JSON → 422; в схеме `additionalProperties: false` | `forbidNonWhitelisted` |

`~partial_of`/`~pick_of` требуют, чтобы `T` был объявлен в том же файле или `T.t` был виден ppx как запись — реализуется через `[@@deriving dto]` на `T`, который дополнительно эмитит `__dto_fields_T` (список полей со схемами) для переиспользования. Это фаза 2; в фазе 1 — только базовый `dto` и `~strict`.

### Варианты

| Форма | JSON |
| --- | --- |
| `A \| B` (без аргументов) | `"a"`: модуль становится `Scalar.S` (`of_string`/`to_string`, JSON Schema `enum`) — годится для пути, query и `[@column string]`; `[@key "x"]` на конструкторе меняет строку |
| `A of int` | `{"tag":"A","value":1}`; `[@@dto ~tag:"type" ~content:"data"]` меняет ключи |
| `A of { x : int }` | `{"tag":"A","x":1}` |
| `t option` | `null` / значение |

### Поведение при ошибке тела запроса

Тело не парсится как JSON → `Error.bad_request` (400). JSON есть, но `Json.parse` вернул `Error errors` (не тот тип, отсутствует поле, нарушено правило) → `Error.unprocessable errors` (422), Problem Details:

```json
{ "type": "urn:kre:error:validation", "title": "Unprocessable Entity", "status": 422,
  "detail": "validation failed", "instance": "/cats",
  "errors": [ { "path": ["age"], "rule": "range", "message": "must be between 0 and 40" } ] }
```

Клиентская часть (`Kre_client.Error`) парсит этот формат; `errors` доступны компоненту формы типизированно.

### Связь с jsonkit (решено в фазе 0)

`dto` **не дублирует** jsonkit: весь JSON в Kre — jsonkit. В jsonkit 1.1.0 (opam) уже есть `[@@deriving json]` (`of_json`/`to_json`, бросают `Jsonkit.Of_json_error`) и `[@@deriving jsonschema]` (`t_jsonschema`) — и в native (`Jsonkit.t = Yojson.Basic.t`), и в melange (`Jsonkit.t = Js.Json.t`); `Jsonkit.Jsonschema.t` на обоих — один и тот же полиморфный вариант. Поэтому:

- `Kre_shared.Json.S` повторяет форму jsonkit-дериверов (`of_json` бросает, имя схемы — `t_jsonschema`), и любой тип с `[@@deriving json, jsonschema]` уже является `Json.S`.
- Граница «исключение → result» — одна функция `Json.parse`, она же превращает `Jsonkit.Of_json_error` в `Validation.t` с правилом `type`.
- Собственный вклад `dto` — правила `[@validate]`, `[@exclude]`/`[@expose]`, `~strict`; накопление ошибок с путями — доработка jsonkit, не Kre.
- jsonkit поставляется двумя библиотеками (`jsonkit`, `jsonkit-melange`), поэтому код, который собирается в обоих режимах, — это две dune-библиотеки с одинаковым `name` из одних исходников (`copy_files#`). Так устроен `kre.shared` / `kre-client.shared`; так же `kre new` будет генерировать `shared/` пользовательского проекта.
- Кодирование вариантов — как у jsonkit (`["A", 1]`), таблица «Варианты» выше будет приведена к нему при реализации `dto` в фазе 1.

## ppx: \[@@deriving config\]

Типизированный конфиг из переменных окружения, с проверкой при старте. Глава Configuration в Nest (`ConfigModule.forRoot` + Joi) сводится к одной записи.

```ocaml
(* server/config.ml *)
type t = {
  port    : int;         [@env "PORT"] [@default 8080]
  db_url  : string;      [@env "DATABASE_URL"]
  secret  : string;      [@env "SESSION_SECRET"] [@secret]
  debug   : bool;        [@env "DEBUG"] [@default false]
  origins : string list; [@env "CORS_ORIGINS"] [@sep ","] [@default []]
}
[@@deriving config]
```

Генерирует:

```ocaml
val load     : ?env:(string -> string option) -> unit -> (t, string list) result
  (* все ошибки сразу: ["DATABASE_URL: missing"; "PORT: not an int: 'abc'"] *)
val load_exn : ?env:(string -> string option) -> unit -> t   (* печатает список и exit 1 *)
val pp       : Format.formatter -> t -> unit                 (* [@secret] печатается как *** *)
```

Поддерживаемые типы полей: `int`, `int64`, `float`, `bool` (`true/1/yes`, `false/0/no` — `Kre.Config.Flag`), `string`, `T.t` с `T : Kre_shared.Scalar.S` (например, `Refined.Email.t`), `τ option` (отсутствие = `None`, `[@default]` запрещён), `τ list` с `[@sep ","]` (один символ). Имя переменной без `[@env]` — имя поля в верхнем регистре. Вложенные записи с `[@prefix "DB_"]` — фаза 2.

Реализация (фаза 1) — интерпретатор: на каждое поле генерируется описание `'a Kre.Config.field`, `load` читает все поля через `Kre.Config.read` и `and+` (ошибки накапливаются), `pp` печатает `NAME=value` по строке через `Kre.Config.show`, `[@secret]` — `Kre.Config.secret field`, печатается как `***`. Эталон — `test/ppx/config.t`.

```ocaml
(* Kre.Config — рантайм [@@deriving config] *)
type env = string -> string option
type ('a, 'b) presence = Required : ('a, 'a) presence | Optional : ('a, 'a option) presence | Default : 'a -> ('a, 'a) presence
type 'a field
val field : string -> (module S : Kre_shared.Scalar.S) -> (S.t, 'b) presence -> 'b field
val list : string -> separator:char -> (module S : Kre_shared.Scalar.S) -> (S.t list, 'b) presence -> 'b field
val secret : 'a field -> 'a field
val read : env -> 'a field -> ('a, string list) result
val show : 'a field -> 'a -> string * string
val pp : Format.formatter -> (string * string) list -> unit
val exit_on_error : ('a, string list) result -> 'a
val dotenv : ?env:env -> string list -> env          (* слои .env под реальным окружением *)
val profile : ?dir:string -> ?env:env -> unit -> env  (* config/default.env, затем config/$KRE_ENV.env *)
module Syntax : sig val ( let+ ) : … val ( and+ ) : … end
module Flag : Kre_shared.Scalar.S with type t = bool
```

`.env`-файлы не меняют окружение процесса (`putenv` не используется): `dotenv`/`profile` возвращают функцию поиска, которая передаётся в `load ~env`. Порядок: реальное окружение → последний файл → … → первый файл; отсутствующий файл пропускается; строки `KEY=VALUE`, `export KEY=VALUE`, кавычки и `#`-комментарии.

## Данные: Db, sqlgg, \[@@deriving table\], миграции

ORM не пишем. Одна глава Data вместо пяти у Nest: запросы — sqlgg, схема — `table`, миграции — `kre migrate`.

### Kre.Db

Реализовано в фазе 1. sqlgg уже содержит traits для MariaDB (`sqlgg.mariadb`: `Sqlgg_mariadb.Make (IO) (Mariadb.Nonblocking.S) (Types)`), поэтому `Kre.Db` не реализует traits, а даёт пул и транзакции; запросы — модули sqlgg, применённые к traits драйвера.

```ocaml
(* Kre.Db — в ядре, без C-зависимостей *)
module type DRIVER = sig
  type conn
  val connect : string -> conn Lwt.t
  val close : conn -> unit Lwt.t
  val start : conn -> unit Lwt.t
  val commit : conn -> unit Lwt.t
  val rollback : conn -> unit Lwt.t
  val query : conn -> string -> string option list -> string option list list Lwt.t   (* фаза 3: ? → $n у Postgres *)
end
module type S = sig
  type conn
  val query : string -> string option list -> string option list list Lwt.t   (* через with_conn: внутри транзакции — в ней *)
  val with_conn : (conn -> 'a Lwt.t) -> 'a Lwt.t                              (* Lwt_pool; внутри транзакции — её соединение *)
  val transaction : (conn -> ('a, 'e) result Lwt.t) -> ('a, 'e) result Lwt.t  (* Ok → commit; Error/исключение → rollback; внутри другой — присоединяется *)
end
module Make (Driver : DRIVER) (Config : sig val url : string val size : int end) : S with type conn = Driver.conn

(* Kre_db_mariadb — отдельный пакет kre-db-mariadb (C-биндинги) *)
module Client : Mariadb.Nonblocking.S with type 'a future = 'a Lwt.t
module Sql : Sqlgg_traits.M_io with type 'a connection = Client.t and type 'a IO.future = 'a Lwt.t
                                and type Types.Int.t = int64 and type Types.Text.t = string
                                and type Types.Bool.t = bool and type Types.Float.t = float
module Driver : Kre.Db.DRIVER with type conn = Client.t      (* mariadb://user:pass@host:port/db?socket=… *)
```

Сервис с базой — функтор: `module Make (Db : Kre.Db.S with type conn = Kre_db_mariadb.Client.t) = struct module Sql = Cats_sql.Make (Kre_db_mariadb.Sql) … end`. `Kre_db_pgx` — фаза 2.

Транзакция как в Spring (фаза 2): `transaction` кладёт своё соединение в ключ Lwt (`Lwt.with_value`, аналог ThreadLocal у `TransactionSynchronizationManager`). Всё, что выполняется внутри неё, — `with_conn` любого сервиса и вложенный `transaction` — берёт это соединение, а не новое из пула. Поэтому сервисам не нужен `~conn` в сигнатуре, чтобы участвовать в транзакции контроллера. Вложенная транзакция — часть внешней (`REQUIRED`): commit или rollback решает внешняя, live-события уходят один раз после её commit. Цена: внутри транзакции запросы идут по одному соединению по очереди, и `Lwt.async`, запущенный внутри, унаследует соединение — фоновую работу запускают после транзакции.

Postgres (фаза 2): драйвер — `Kre_db_postgresql` на libpq (пакет `postgresql`), не pgx. Причина: sqlgg-traits требуют `execute_response.affected_rows`, а pgx число изменённых строк читает, но наружу не отдаёт; libpq отдаёт (`cmd_tuples`). Запросы libpq идут через `Lwt_preemptive.detach`: сокет libpq — `int`, а превратить его в `Unix.file_descr` без `Obj.magic` нельзя. Ограничения sqlgg для `-dialect postgresql`: нет `RETURNING`, `BIGSERIAL`, `GENERATED … AS IDENTITY`. Поэтому ключ `[@primary] [@auto]` — `SERIAL`, а `insert_id` драйвер заполняет через `SELECT lastval()` на том же соединении, и сервисы пишутся одинаково для обеих БД. `Kre.Table.schema` получает диалект: у Postgres `DOUBLE PRECISION` и отдельный `CREATE INDEX`; CRUD-запросы общие.

### sqlgg

Связка `table` + sqlgg — флагманская возможность Kre, которой нет ни у Nest, ни у Rails: **схема — это OCaml-тип, и каждый SQL-запрос проверяется против неё компилятором.** Цепочка:

1. `[@@deriving table]` на записи генерирует `schema : Kre.Table.t` и dune-правило пишет из всех таких типов `schema.sql` (DDL под выбранный диалект).
2. sqlgg получает `schema.sql` + пользовательские запросы (`queries/*.sql` или inline через `ppx_sqlgg`) и генерирует типизированные функции; nullability выводится lattice-анализом из форка и совпадает с `option` в записях.
3. Результаты запросов отображаются в записи через сгенерированный `table`-ом `of_row` (по именам колонок), поэтому `SELECT id, name FROM users` → `User.t`-совместимый тип без ручного маппинга.
4. `kre migrate diff` сравнивает тот же `schema` со снапшотом и готовит черновик миграции.

Эффект: переименовал поле `email` в записи — не компилируются DTO, клиент, loader на фронте, **и все SQL-запросы, где оно упоминается**, а `kre migrate diff` предлагает `ALTER TABLE`. Ни один слой не узнаёт о расхождении в рантайме.

Пример запроса (sqlgg, файл `queries/users.sql`):

```sql
-- @find_adults_by_breed
SELECT u.id, u.email, u.name, u.age
FROM users u JOIN cats c ON c.owner_id = u.id
WHERE c.breed = @breed AND u.age >= @min_age
```

сгенерированная сигнатура (под `Kre.Db` как sqlgg-traits):

```ocaml
val find_adults_by_breed : Db.conn -> breed:string -> min_age:int -> User.t list Lwt.t
```

Использование в сервисе — обычный вызов; контроллер его не видит. Kre здесь добавляет три вещи: `Kre.Db` реализует sqlgg-traits (IO = Lwt, параметры, строки); `table` эмитит `schema.sql` и `of_row`; шаблон `kre new` содержит dune-правила для всей цепочки. Сам sqlgg не форкается дальше и не оборачивается.

### &#91;@@deriving table\]

Реализовано: DDL и `of_row` (фаза 1); CRUD (фаза 2) — `Kre.Table.crud` печатает SQL, sqlgg генерирует модуль, деривер даёт `for_insert`/`for_update`. Один общий `spread` невозможен: метки не переставляются у параметра без аннотации типа, а у sqlgg `update` ставит ключ последним, `insert` его не принимает.

```ocaml
type t = {
  id : int; [@primary] [@auto]
  name : Name.t; [@column string] [@size 64]
  age : Age.t; [@column int]
  breed : Breed.t; [@column string] [@size 32] [@index]
}
[@@deriving table ~name:"cats", dto]
(* → table : Kre.Table.t
     of_row : id:int64 -> name:string -> age:int64 -> breed:string -> t   (форма колбэка sqlgg) *)
```

- Типы колонок: `int`/`int64` → `BIGINT`, `string` → `VARCHAR(size)` или `TEXT`, `bool` → `BOOLEAN`, `float` → `DOUBLE`, `τ option` → `NULL`. Поле абстрактного типа `T.t` (`Refined`) требует `[@column int|string|bool|float]`: ppx не видит представление `T.t`, а тип аргумента `of_row` обязан совпасть с тем, что даёт sqlgg; значение проходит `T.of_string` (`Kre.Table.decode`), то есть правила `Refined` проверяются и на чтении из базы. Время — `Kre_shared.Time.t` (фаза 3, без `[@column]`): в базе `DOUBLE` секунд, на проводе RFC 3339; не `Ptime` и не `TIMESTAMP`, потому что тип нужен и в Melange, а `TIMESTAMP` sqlgg типизирует по-разному в MySQL и Postgres.
- Атрибуты: `[@primary]`, `[@auto]` (только с `[@primary]`), `[@unique]`, `[@index]` — одна роль на поле; `[@size n]`; `[@references M]` → `FOREIGN KEY … REFERENCES <M.table> (id)`; `[@sql.default "SQL"]` — не `[@default]`, потому что `[@default]` уже значит дефолт jsonkit-деривера (OCaml-значение, а не SQL).
- `[@created_at]`, `[@updated_at]` (поле `Kre_shared.Time.t`) и `[@version]` (`int`) — фаза 3, как timestamps и `lock_version` в Rails, auditing и `@Version` в JPA. `for_insert` ставит обе метки в `Kre.Table.now ()` и версию 0; `for_update` обновляет `updated_at`, не трогает `created_at` и передаёт прочитанную версию; `crud` печатает `UPDATE … SET …, version = version + 1 WHERE id = @id AND version = @version`. 0 изменённых строк — запись изменили после чтения: сервис отвечает 409 (`examples/shelter/server/cats_service.ml`, `rename`). Пока примеры не выпущены, `0001_init.sql` перегенерируется; после выпуска миграции только добавляются (`kre migrate diff` — фаза 3).
- `Kre.Table.schema [ Cat.table; … ]` печатает DDL (MariaDB/MySQL). Реестра нет: `schema.sql` собирает маленький бинарь со списком таблиц, dune-правило передаёт его sqlgg (`examples/cats/db/dune`): `sqlgg -dialect mysql -gen caml_io -name Make schema.sql queries/cats.sql`.
- Под Melange (`(pps … kre-ppx -- -melange)`) `table` ничего не генерирует, `dto` на том же типе работает.
- Проверено на живой MariaDB 11.8: `examples/cats/db` (вставка через контроллер, чтение `Sql.List.all conn ~limit Cat.of_row` и `Sql.Single.by_id`, откат транзакции); алиас `dune build @examples/cats/db/test/db` с `KRE_TEST_DB_URL`.

### Миграции

Фаза 1 (реализовано): `migrations/NNNN_name.sql` с секциями `-- migrate:up` и `-- migrate:down`; выражение заканчивается `;` в конце строки, строки-комментарии `--` пропускаются. Применённые версии — в таблице `kre_migrations (version, applied_at)`, она создаётся при первом обращении.

```ocaml
(* Kre.Migration — поверх того же Kre.Db.DRIVER (в нём есть execute и strings) *)
type t = private { version : string; up : string list; down : string list }
type state = Applied | Pending
val parse : version:string -> string -> (t, string) result
val load : string -> (t list, string) result             (* каталог, по имени файла *)
val create : dir:string -> string -> string              (* следующий NNNN_name.sql *)
val status : (module D : Db.DRIVER) -> D.conn -> t list -> (t * state) list Lwt.t
val up : (module D : Db.DRIVER) -> D.conn -> t list -> t list Lwt.t        (* все ожидающие, по порядку *)
val down : (module D : Db.DRIVER) -> D.conn -> t list -> t option Lwt.t    (* последнюю применённую *)
```

В приложении миграции встраиваются в бинарь: `Kre.Migration.of_files [%embed_dir "migrations"]` — ppx `[%embed_dir]` раскрывается в список `(файл, содержимое)` при сборке (dune: `(preprocessor_deps (glob_files migrations/*.sql))`), поэтому сервер не зависит от рабочего каталога. CLI: `kre migrate up|down|status --url URL --dir migrations` (`--url` или `DATABASE_URL`), `kre migrate new NAME`. MariaDB коммитит DDL неявно, поэтому миграция из нескольких выражений не атомарна: при сбое посередине база остаётся в промежуточном состоянии, версия не записывается. Проверено на MariaDB (`examples/cats/db/test`, алиас `@db`): пустая база → `up` → схема на месте → `down`, плюс те же шаги через CLI.

Фаза 3: `kre migrate diff` сравнивает `schema` всех `table`-типов со снапшотом и генерирует SQL-черновик, который разработчик правит руками; у sqlgg уже есть `-diff`/`-migrate`, сначала проверить их. Автоприменение диффа без просмотра — никогда.

## Генерация клиента и OpenAPI из spec

Контракт живёт в контроллере; `spec` — его рантайм-отражение; всё остальное — кодогенерация из `spec`. Нет отдельного «файла контракта», который мог бы разойтись с кодом.

### Цепочка

1. ppx эмитит в каждый контроллер `spec : Kre.Spec.t`.
2. `Kre.App.run` получает список контроллеров, а с ним и все `spec` — отдельный реестр не нужен.
3. С флагом `--emit-spec FILE` (JSON-массив `Spec.to_json`) или `--emit-openapi FILE` `App.run` пишет файл и не стартует сервер; `kre` читает массив обратно через `Spec.of_json`.
4. `kre client --spec spec.json --out client/gen/` пишет melange-модули; dune rule в шаблоне проекта запускает шаги 3–4 автоматически:

```
(rule (targets spec.json) (deps %{exe:../bin/main.exe})
      (action (run %{exe:../bin/main.exe} --emit-spec spec.json)))
(rule (targets cats_client.ml) (deps spec.json)
      (action (run kre client --spec spec.json --controller cats --out cats_client.ml)))
```

### Генерируемый клиент

На каждый контроллер — модуль `<prefix>_client` (`kre client --spec spec.json --controller cats --out cats_client.ml`). Эталон для cats:

```ocaml
let find_all ?limit () =
  Kre_client.Http.request `GET
    ~path:[ "cats" ]
    ~query:[ Kre_client.Wire.query (module Kre_shared.Scalar.Int) Kre_shared.Presence.Optional "limit" limit ]
    (Kre_client.Wire.Json (module Kre_shared.Json.List (Cat)))

let find_one ~id =
  Kre_client.Http.request `GET
    ~path:[ "cats"; Kre_client.Wire.segment (module Kre_shared.Scalar.Int) id ]
    (Kre_client.Wire.Json (module Cat))

let create ~body =
  Kre_client.Http.request `POST ~path:[ "cats" ]
    ~body:(Kre_client.Wire.body (module Create_cat_dto) body)
    (Kre_client.Wire.Json (module Cat))
```

Правила: path-параметры → `~name`, query `Required`/`Repeated` → `~name`, `Optional` → `?name`, тело → `~body`; `()` в конце, если параметров нет или есть необязательные. Guard-параметры в клиент не попадают. Типы не печатаются: их выводит компилятор из модулей в `spec` (`value.module_`), поэтому DTO обязаны лежать в `shared/`. Путь собирается из сегментов (`Wire.segment` кодирует), без библиотеки routes: она не собирается под Melange.

**Один и тот же сгенерированный файл** компилируется против двух библиотек с одним именем `Kre_client`: `kre-client` (Melange, `fetch`, `Js.Promise.t`) и `kre-client.native` (cohttp, `Lwt.t`). Флаг `--target` не нужен. Native-вариант используется в e2e: `examples/cats/client_native` генерирует клиент dune-правилом из `main.exe --emit-spec` и гоняет его против живого сервера.

### Kre\_client.Http и Wire

```ocaml
(* общие для обоих бэкендов *)
module Wire : sig
  type verb = [ `GET | `POST | `PUT | `PATCH | `DELETE ]
  type response = { status : int; body : string }
  type 'a returns = Unit : unit returns | Text : string returns
                  | Json : (module Kre_shared.Json.S with type t = 'a) -> 'a returns | Raw : response returns
  val segment : (module S : Kre_shared.Scalar.S) -> S.t -> string
  val query : (module S : Kre_shared.Scalar.S) -> (S.t, 'b) Kre_shared.Presence.t -> string -> 'b -> (string * string) list
  val body : (module J : Kre_shared.Json.S) -> J.t -> string
  val url : base:string -> path:string list -> query:(string * string) list list -> string
  val decode : 'a returns -> response -> ('a, Error.t) result
end
module Error : sig
  type problem = { status : int; type_ : string; title : string; detail : string; errors : Kre_shared.Validation.error list }
  type t = Problem of problem | Network of string | Decode of Kre_shared.Validation.t
  val of_response : status:int -> string -> t
  val message : t -> string
end
(* свой у каждого бэкенда; promise = Js.Promise.t или Lwt.t *)
module Http : sig
  val base_url : string ref                       (* "" = same origin; ?base у request — фаза 3, [%http_client] *)
  val headers : (string * string) list ref        (* auth, csrf — упрощённые interceptors *)
  val request : Wire.verb -> path:string list -> ?query:(string * string) list list -> ?body:string ->
    'a Wire.returns -> ('a, Error.t) result promise
  (* только native, фаза 3: куда идут запросы *)
  type exchange = { verb : Wire.verb; target : string; headers : (string * string) list; body : string option }
  type transport = Network | Local of (exchange -> Wire.response Lwt.t)
  val transport : transport ref
end

(* kre-client.testing — фаза 3; Nest Testing + supertest, Spring MockMvc *)
module Kre_testing : sig
  val use : ?middleware:Dream.middleware list -> Kre.Controller.t list -> unit   (* transport := Local (App.handler …) *)
end
```

Тест вызывает те же сгенерированные функции, что и фронтенд (`Cats_client.create ~body`), но без сокета: `Kre_testing.use` подменяет транспорт на обработчик приложения в том же процессе. Ошибка в пути, теле или типе ответа — ошибка компиляции теста, а не 400 в рантайме; пример — `examples/cats/client_native/test_in_process.ml`.

### OpenAPI

`--emit-openapi` (и `kre openapi --spec`) строит документ 3.1 через `Kre.Openapi.document ~title ~version specs`: `paths` из `spec.routes`, `components.schemas` из `jsonschema` всех встреченных DTO (имя модуля = имя схемы), `parameters` из `Codec.schema`, `responses` с кодом из `status` и envelope ошибки для 4xx. Теги — префиксы контроллеров. Описания операций — атрибуты `[@@summary "…"]` и `[@@description "…"]` на хендлере (как `@ApiOperation`), они попадают в `Spec.route` и OpenAPI; docstrings не используются, потому что комментарии над функциями запрещены правилами кода. Схемы DTO с простым именем модуля (`Cat`) уходят в `components.schemas` и подключаются `$ref`; остальные (`Kre_shared.Scalar.Int`, `Kre_shared.Json.List (Cat)`) встраиваются. Ошибки — `default`-ответ `application/problem+json` со схемой `Problem`. Документ cats проходит `openapi-spec-validator` (шаг CI). Swagger UI — фаза 2.

## Frontend: Kre\_client и typed router

Модель — TanStack Router: маршрут как значение с типами `params`/`search`/`data`, `Link` и `navigate` проверяются компилятором, loader на маршруте, вложенные layouts. React — через reason-react, разметка — `.mlx`.

### Kre\_client.Router

Реализовано в фазе 1 (`src/client/router.ml`):

```ocaml
type parent                                         (* layout'ы вокруг маршрутов *)
type ('p, 's, 'd) route
type any = Any : ('p, 's, 'd) route -> any
type t

val root : ?layout:(children:React.element -> React.element) -> unit -> parent
val nest : parent -> layout:(children:React.element -> React.element) -> parent
val no_data : 'p -> 's -> unit Js.Promise.t
val child :
  ?live:string list ->                              (* фаза 2: перезапуск loader по /__kre/live *)
  parent -> path:'p Path.t -> search:'s Search.t ->
  loader:('p -> 's -> 'd Js.Promise.t) ->
  component:(data:'d -> params:'p -> search:'s -> React.element) -> ('p, 's, 'd) route
val make : any list -> t
val href : ('p, 's, _) route -> params:'p -> search:'s -> string
val navigate : ('p, 's, _) route -> params:'p -> search:'s -> unit
val link : ('p, 's, _) route -> params:'p -> search:'s -> children:React.element -> React.element
module View : sig   (* <View router /> *)
  val make : router:t -> ?server_url:string -> ?pending:React.element -> ?not_found:React.element -> unit -> React.element
  [@@react.component]
end
```

Отличия от первой версии (фаза 1):
- `?search` и `?loader` «по умолчанию unit» не типизируются в OCaml (необязательный аргумент не может менять тип результата), поэтому они обязательны: `~search:Kre_shared.Search.none`, `~loader:Kre_client.Router.no_data`.
- Пути маршрутов абсолютные; родитель (`parent`) даёт только layout'ы. Параметры родителя не наследуются — запись `params` описывает весь путь.
- `link` — функция, а не полиморфный компонент: ошибка в `params` — ошибка типов на вызове (`test/router/link.t`).
- Матчинг — сверху вниз по списку `make`; неразобранный `search` — как отсутствие маршрута (`not_found`). Loader вызывается в `useEffect` при смене URL; ответ устаревшего URL отбрасывается по ключу. Кэш loader'ов, `preload`, `use_params`/`use_search`/`use_loader_data`, `on_error` — фаза 2.
- URL читается через `ReasonReactRouter.useUrl`; `?server_url` — для серверного рендера.

### Path, Search, Params — ppx в kre-ppx

Библиотека routes не собирается под Melange, поэтому `Kre_client.Path` — свой: шаблон сегментов + `decode`/`encode` в ассоциативный список. Путь и тип параметров объявляются вместе, чтобы ppx сверил имена:

```ocaml
type params = { id : int } [@@deriving params ~path:"/cats/:id"]   (* → params_path : params Kre_client.Path.t *)
type search = { limit : int; [@default 20] breed : string option } [@@deriving search]   (* → search_codec : search Kre_shared.Search.t *)
let index = Kre_client.Router.child root ~path:[%path "/cats"] ~search:search_codec …   (* [%path] — только без параметров *)
```

`params`: поле на каждый `:name` и наоборот, иначе ошибка со списком расхождений; типы полей — `Scalar.S`. `search`: `τ option` — необязательный, `τ list` — повторяемый, `[@default e]` — с дефолтом, иначе обязательный; ошибки разбора — `Validation.t` с путём `[name]`. Типы — те же `Kre_shared.Scalar`, что у сервера и клиента API.

### Почему контроллер не принимает путь страничного роутера (решено после фазы 1)

Рассматривали `[@@get Cat_routes.params_path]` с общим для сервера и фронта `Path` и хендлером `~(params : Cat_routes.params)`. Не делаем:

- Дублирования, которое это убрало бы, почти нет. Клиент API уже генерируется из `spec` контроллера. Совпадают только пути страницы и API, но это разные вещи: в реальном приложении API уходит под `/api` или `/v2`, а страницы называются как удобно пользователю.
- ppx перестал бы видеть сегменты пути в тексте. Сверку `:id` с параметром, `Paths` на routes и `spec` пришлось бы перенести в рантайм, а сейчас всё это проверяется при компиляции.
- Хендлер стал бы принимать запись вместо меток (`~id`), то есть дальше от Nest. Пришлось бы иметь две реализации матчинга или отказаться от trie routes на сервере.

Строковые пути в контроллере уже типизированы: ppx строит `Routes.path` из строки и типов меток, а `Cats_controller.Paths` даёт типизированные значения для ссылок и тестов. Вернуться к вопросу, если появится реальный случай, где путь страницы и API обязаны совпадать.

### Компоненты

`Link` — обычный компонент reason-react над `Router.link`; `.mlx`-синтаксис даёт `<Link route=… params=… search=…>`. Ошибка в `params` — ошибка типов в компоненте, не в рантайме.

JSX пишется только в `.mlx`: диалект подключён в `dune-project` (`mlx-pp` для сборки, `ocamlformat-mlx` 0.29.0.1 для `@fmt`), ручных `[@JSX]` и `React.createElement` нет ни в примерах, ни в `src/client/router.mlx`.

### Что не делаем

File-based routing (`routes/cats.$id.tsx`) — не нужен: дерево из значений даёт то же самое без кодогенерации по файловой системе. SSR Melange-компонентов — не в скоупе; серверный HTML — Dream eml/tyxml как опция.

## Тестирование

Четыре уровня, каждый — свой каталог в `test/`. Nest-овский `Test.createTestingModule` не нужен: подмена зависимости — применение функтора/`register` к другому модулю.

| Уровень | Инструмент | Что проверяет |
| --- | --- | --- |
| ppx | cram на выводе `pp.exe -impl` | каждая трансформация: эталонный сгенерированный код; каждая ошибка ppx — отдельный тест с ожидаемым сообщением |
| core | alcotest | `Error.to_response`, `Codec`, `Validation`, `Refined`, `Spec.to_json`, OpenAPI-генератор, `Route.handle` с подменённым запросом |
| контроллеры (unit) | alcotest + `Dream.test` | `Cats_controller.register (module Fake_cats)` → `Kre.App.handler` → `Dream.test handler (Dream.request ~method_:`GET \~target:"/cats/1" "")\` → статус/тело |
| e2e | alcotest, запуск `examples/cats` | сервер на случайном порту; сгенерированный native-вариант клиента (тот же генератор с `--target native` поверх cohttp) ходит по всем маршрутам; OpenAPI валидируется схемой 3.1 |

Пример unit-теста контроллера с фейковым сервисом:

```ocaml
module Fake_cats : Cats_service.S = struct
  let add _ = Lwt.return { Cat.id = 1; name = "x"; age = 1; breed = "siamese" }
  let find_all () = Lwt.return []
  let find = function 1 -> Lwt.return_some { Cat.id = 1; … } | _ -> Lwt.return_none
end

let app = Kre.App.handler [ Cats_controller.register (module Fake_cats) ]

let test_404 () =
  let%lwt resp = Dream.test app (Dream.request ~method_:`GET ~target:"/cats/2" "") in
  Alcotest.(check int) "status" 404 (Dream.status resp |> Dream.status_to_int);
  Lwt.return_unit
```

Клиентский роутер тестируется в node через melange: `Path` матчинг и `Search` round-trip — property-тесты (`Search.parse (Search.print s) = Ok s`). Если принят typegist, генераторы для property-тестов берутся из gist.

## CLI kre

Бинарь на cmdliner, зеркало `nest` CLI. Генераторы пишут файлы по шаблонам из `examples/cats`; ничего не делают «магически» — только файлы, которые разработчик и так написал бы руками.

| Команда | Делает | Nest |
| --- | --- | --- |
| `kre new NAME` | dune-project, 4 каталога, cats-пример, CI, `.ocamlformat`, opam-файлы | `nest new` |
| `kre generate controller cats` | `server/cats_controller.ml` с `[@@@controller]` и CRUD-заготовкой, `shared/cat.ml`, `shared/create_cat_dto.ml` | `nest g resource` |
| `kre generate service cats` | `server/cats_service.ml` + `.mli` с `module type S` | `nest g service` |
| `kre generate dto name` | `shared/name_dto.ml` | — |
| `kre client --spec --out [--target melange\|native]` | типизированные клиенты из spec | openapi-generator |
| `kre openapi --spec --out` | OpenAPI 3.1 JSON; то же, что `main.exe --emit-openapi` | `@nestjs/swagger` |
| `kre migrate up\|down\|status\|new NAME` | SQL-миграции (фаза 1), `diff` (фаза 3) | TypeORM CLI |
| `kre routes` | таблица маршрутов из spec | — |
| `kre start [--watch]` | `dune build -w` + перезапуск `main.exe`; melange-пересборка — через dune же | `nest start --watch` |

`kre routes`, `kre openapi` и `kre client` читают `spec.json`, который пишет серверный бинарь (`--emit-spec`), поэтому сериализация `spec` одна. Шаблоны — файлы `src/cli/templates/<new|controller|service|dto>/…/*.tmpl` (`data_only_dirs`); при сборке `embed.exe` встраивает их в бинарь. Подстановки — `{{name}}`, `{{plural}}`, `{{Plural}}`, `{{singular}}`, `{{Singular}}`, в путях — слова `plural`/`singular`; единственное число — без конечной `s`. `kre new` пока без клиента и без БД: `shared/` (native + melange), `server/` с health-контроллером, `bin/main.ml`, тест; `generate controller` — ресурс как `nest g resource` (тип и DTO в `shared/`, сервис в памяти, контроллер, тест в `test/<plural>/`), регистрацию в `main.ml` разработчик добавляет сам. Перезаписи нет: если хоть один файл существует, не пишется ничего.

## Заимствования из Spring

Nest задаёт структуру; из Spring берём пять вещей, которых у Nest нет или они слабее. Все пять в Spring реализованы runtime-прокси (AOP); у нас это compile-time переписывание ppx, поэтому ловушек вроде self-invocation нет.

| Spring | Kre | Фаза |
| --- | --- | --- |
| Problem Details (RFC 9457, `application/problem+json`) | формат `Error.to_json` и клиентского `Error.t` | 0 |
| `@PreAuthorize("… #id == principal.id")` | `[@@authorize f]` — типизированная функция над извлечёнными параметрами | 2 |
| `@Transactional` | `[@@transactional]`; соединение — неявно через ключ Lwt (или явно `[@from Db.tx]`) | 2 |
| Actuator | `Kre.Actuator.routes` | 2 |
| Profiles | `KRE_ENV` + слои `config/*.env` — сделано | 1 |

### Problem Details — заменяет envelope ошибки

Этот формат **заменяет** JSON ошибки, описанный в разделах Core и dto. `Error.t` остаётся тем же, меняется сериализация:

```json
{ "type": "urn:kre:error:validation", "title": "Unprocessable Entity", "status": 422,
  "detail": "validation failed", "instance": "/cats",
  "errors": [ { "path": ["age"], "rule": "range", "message": "must be between 0 and 40" } ] }
```

`type` = `urn:kre:error:<code>` (переопределяется `Error.make ~type_`), `instance` = `Dream.target`, `details` раскладываются как расширения верхнего уровня. Content-Type `application/problem+json`. `Kre_client.Error` парсит ровно это.

### `[@@authorize]`

Реализовано в фазе 2. Замыкание вызывается после разбора всех параметров (path, query, body, `[@from]`) и до тела; ему передаются аргументы хендлера с теми же метками.

```ocaml
let read ~(user : string [@guard Roles.user]) ~(id : int) : string Lwt.t = …
[@@get ":id"] [@@authorize fun ~user ~id -> owns ~user ~id]
```

- Payload — буквальная функция `fun ~a ~b -> …`: по меткам ppx решает, что передать. Метка, которой нет у хендлера, — ошибка компиляции; тип проверяет компилятор.
- Результат — только `(unit, Kre.Error.t) result Lwt.t`; вариант с `bool Lwt.t` из первой версии убран (булева слепота). `Error e` становится ответом (обычно 403).
- Зависимости хендлера доступны замыканию по имени: оно генерируется внутри `register`, где модули уже связаны.

Отличие от `[@@guards]`: guard видит только запрос, `authorize` — типизированные параметры. Пример — `docs/examples/notes_controller.ml`.

### `[@@transactional]`

Реализовано в фазе 2:

```ocaml
let adopt (module Adoptions : Adoptions_service.S)
    (module Db : Kre.Db.S with type conn = Kre_db_mariadb.Client.t)
    ~(user : User.t [@guard Auth.current]) ~(body : Adopt_dto.t)
    : (Adoption.t, Kre.Error.t) result Lwt.t =
  Adoptions.adopt body.cat_id user.id
[@@post] [@@transactional]
```

Как `@Transactional` в Spring: соединение в коде не видно, сервисы внутри пользуются обычным `Db.with_conn` и попадают в транзакцию (см. «Kre.Db»). В Nest такого декоратора нет — там `dataSource.transaction(…)`/`QueryRunner` руками или сторонний `@nestjs-cls/transactional`.

`Kre.Db.S` получил `tx : conn Guard.t` (читает соединение из поля запроса) и `within : Dream.request -> (unit -> ('a, Error.t) result Lwt.t) -> ('a, Error.t) result Lwt.t` (открывает транзакцию или присоединяется к открытой, кладёт соединение в поле, `Ok` → commit, `Error`/исключение → rollback). ppx берёт модуль из единственной зависимости `Kre.Db.S` хендлера или из параметра `[@from M.tx]`, если он есть (тогда соединение приходит параметром явно, как `examples/cats/db/batch_controller.ml`), и оборачивает разбор параметров и вызов хендлера в `M.within`; guards выполняются до транзакции. `[@@transactional]` без зависимости `Kre.Db.S`, с двумя такими без `[@from M.tx]`, и `[@from M.tx]` без `[@@transactional]` — ошибки компиляции. Опции изоляции и `read_only` — когда понадобятся. Пример — `examples/shelter/server/adoptions_controller.ml`; проверки — алиасы `@db` и `@shelter`.

### Actuator

`Kre.Actuator.routes : config:(module Config.S) -> ?metrics:bool -> unit -> Kre.Controller.t`, монтируется как обычный контроллер под `/actuator`:

| Путь | Содержимое |
| --- | --- |
| `/health` | `{"status":"up","checks":{"db":"up"}}`; проверки регистрируются `Actuator.check ~name f` |
| `/info` | версия, git sha, время сборки (из dune `%{version}` и `git describe` в сборке) |
| `/env` | конфиг через `Config.pp` — `[@secret]` замазаны |
| `/routes` | все `spec` в JSON — то же, что `kre routes` |
| `/beans`, `/beans.mmd` | граф `[%wire]`: провайдеры и контроллеры с их зависимостями (JSON, mermaid); `Actuator.make ~beans:app.beans` |
| `/metrics` | Prometheus text format: latency по маршруту, коды, `Gc.quick_stat` |
| `/openapi.json` | то же, что `--emit-openapi` |

Закрывается `[@@@guards]` как любой контроллер; по умолчанию — только с loopback.

### Profiles

`Kre.Config.profile ()` читает `config/default.env`, затем `config/${KRE_ENV}.env` (по умолчанию `dev`), затем реальное окружение; позже — приоритетнее. Использование: `Config.load_exn ~env:(Kre.Config.profile ()) ()`. Условные провайдеры в `main.ml` — обычный `match config.env with`; атрибут `[@profile]` не нужен.

## Заимствования из IHP

IHP (Rails для Haskell) силён там, где Nest и Spring пусты: живые данные без ручных подписок, веб-инструменты разработчика и DB-backed jobs. Берём четыре идеи; одна из них у нас получается строже, чем в IHP.

| IHP | Kre | Фаза |
| --- | --- | --- |
| Auto Refresh (страница обновляется при изменении таблиц, которые она читала) | Live loaders: зависимости маршрута от таблиц известны **статически** из sqlgg | 2 |
| Scripts (одноразовые скрипты с контекстом приложения) | `[@@command]` (фаза 3, `docs/commands.md`) вместо `kre generate script` + `kre run NAME` | 3 |
| Jobs как таблицы (`CREATE TABLE … job`) | `Kre.Job` (фаза 3): одна таблица `kre_jobs` и типизированные очереди вместо таблицы на тип задачи | ✅ |
| IDE: Schema Designer, Data browser, Logs | `kre dev` — веб-UI поверх Actuator | 3 |
| Schema.sql как источник правды, типы из него | **не берём** направление, берём импорт: `kre import-schema` для brownfield | 1 |

### Live loaders — Auto Refresh через статический анализ

IHP отслеживает таблицы, прочитанные при рендере, в рантайме, и слушает Postgres `LISTEN/NOTIFY`. У нас обе половины известны на этапе компиляции, потому что sqlgg парсит SQL:

1. sqlgg знает, какие таблицы **читает** каждый запрос и какие **пишет** (`INSERT/UPDATE/DELETE`). Kre расширяет сгенерированный код метаданными `reads : string list`, `writes : string list` на функцию.
2. Хендлер, вызывающий сервисные функции, не знает их таблиц статически (это уже за пределами ppx). Поэтому зависимости объявляются на хендлере: `[@@live ["cats"; "users"]]`, а e2e-тест проверяет, что объявленное ⊇ фактически прочитанного (рантайм считает `reads` вызванных sqlgg-функций в режиме `KRE_ENV=test`). Расхождение — падение теста, не тихая потеря обновлений.
3. После коммита транзакции (или после любой пишущей sqlgg-функции вне транзакции) `Kre.Live.publish` рассылает `Table_changed t` — без триггеров в БД, поэтому работает и на MariaDB/TiDB, где нет `NOTIFY`. Для Postgres опционально `LISTEN/NOTIFY`, чтобы ловить внешние записи.
4. `spec.route.live : string list` попадает в сгенерированный клиент: `Cats_client.find_all` получает `~subscribe:true`, а `Router.child ~live:true` перезапускает loader при событии по SSE-каналу `/__kre/live`. Для multi-process — pub/sub через Redis или Postgres; один процесс — in-memory.

Результат: `Cats.index` на фронте обновляется, когда кто-то добавил кота, без единой строки кода подписки в приложении — и с проверяемым списком зависимостей.

### Scripts

`kre generate script backfill_ages` создаёт `scripts/backfill_ages.ml` с заготовкой `let main (module Db : Db.S) (config : Config.t) = …`; `kre run backfill_ages` собирает и запускает с тем же `Config.load` и пулом, что и сервер. Это замена `rake`-задачам и «вот бы быстро прогнать одну миграцию данных».

### Jobs как таблицы

Сделано в фазе 3 иначе, чем ниже: одна таблица `kre_jobs` с JSON-нагрузкой и очереди `'a Kre.Job.queue` (имя + dto). Таблица на тип задачи дала бы миграцию и сгенерированный код на каждую очередь, а тип нагрузки всё равно проверяет dto. См. `docs/jobs.md`. Исходный набросок:

```ocaml
type t = { id : int [@primary] [@auto]; cat_id : int; email : string }
[@@deriving table ~name:"send_welcome_jobs" ~job]
```

`~job` добавляет колонки `status`, `attempts`, `run_at`, `last_error`, `locked_by` и генерирует `enqueue : t -> unit Lwt.t` и `Worker.run ~handler:(t -> (unit, string) result Lwt.t) ~concurrency ~retry`. Очередь — сама таблица с `SELECT … FOR UPDATE SKIP LOCKED`; никакого Redis для базового случая. Это реализация главы Queues (фаза 3) по умолчанию; BullMQ-подобный бекенд — только если понадобится.

### kre dev

Веб-UI на том же порту под `/__kre/`: список маршрутов (`spec`), схема и данные таблиц (из `Kre.Table.Registry` + sqlgg-запросов, редактирование строк), логи запросов в реальном времени (SSE), статус live-подписок, OpenAPI. Schema Designer как в IHP не делаем: схема — OCaml-код, редактор ей не нужен. Включается только при `KRE_ENV=dev`.

### Направление истины: тип, не SQL

IHP держит `Schema.sql` и генерирует типы. Мы держим OCaml-записи (там живут opaque-типы и `dto`) и генерируем `schema.sql`. Для brownfield (существующая MariaDB/TiDB) — `kre import-schema --url … --out shared/gen/`: sqlgg парсит `SHOW CREATE TABLE` и пишет записи с `[@@deriving table, dto]`, которые дальше правятся руками и становятся источником. Одноразовый импорт, не двусторонняя синхронизация.

## Заимствования из Rails, Symfony и ещё раз Spring/Nest/IHP (фаза 3)

Правило переноса то же: только функции, модули, функторы и ppx; никаких классов, рефлексии и рантайм-реестров. Если идея в оригинале держится на рантайм-магии (ActiveRecord callbacks, Doctrine proxies, AOP), берём результат, а механизм заменяем проверкой при сборке. Что уже есть (контроллеры, DI, guards, interceptors, dto, config, events, cron, cache, SSE/WS, JWT, Actuator, live loaders, table + sqlgg, миграции, typed client и router, `[@@transactional]`, `[@@authorize]`), сюда не входит.

| # | Откуда | Kre | Волна |
| --- | --- | --- | --- |
| 1 | Spring Data derived queries (`findByStatus`), Rails `find_by`/`where`, Doctrine `findBy` | `Kre.Table.crud` печатает `by_<col>` для `[@unique]` (одна строка), `[@index]` и `[@references]` (список) и `count`; sqlgg их типизирует | ✅ |
| 2 | Rails `fresh_when`/ETag, Spring `ShallowEtagHeaderFilter`, Symfony `isNotModified` | `[@@etag]` на GET: ETag из тела, `If-None-Match` → 304 | ✅ |
| 3 | Spring Retry `@Retryable`, Symfony Messenger retry | `[@@retry n]` `[@@backoff s]` на любой функции → `Kre.Retry.run`; повтор при исключении. Не interceptor: в Spring это аннотация метода сервиса, и у нас тоже | ✅ |
| 4 | Nest Devtools (граф модулей), Spring `/actuator/beans` | `[%wire]` отдаёт граф (`Wiring.beans`); `/actuator/beans` (JSON) и `/actuator/beans.mmd` (mermaid) | ✅ |
| 5 | Nest `Test.createTestingModule` + supertest, Spring MockMvc, Rails integration tests, Symfony `WebTestCase` | `kre-client.testing`: сгенерированный типизированный клиент идёт в обработчик приложения без сокета (`Kre_testing.use`) | ✅ |
| 6 | Symfony `#[MapQueryString]`, Nest `@Query() dto`, Spring `@ModelAttribute` | query-строка целиком в запись с `[@@deriving search, dto]`: `~(search : (Cat_search.t[@search]))`. Кодек переехал в `Kre_shared.Search` (native и Melange): один `Cat_search.codec` у сервера (`Kre.Extract.search`), у страничного роутера и у клиента (`Spec.Search`, `Wire.search`) | ✅ |
| 7 | Spring `Pageable`/`Page`, kaminari, Pagerfanta | `Kre_shared.Page`: `Request.t` — готовая search-запись (`?page&size`, page ≥ 1, size 1–100) для `[@search]`; `'a t` с `total`; `-- @page` (`LIMIT/OFFSET`) в `Table.crud`; возврат `Cat.t Kre_shared.Page.t`, клиент получает тот же тип | ✅ |
| 8 | Symfony Console `#[AsCommand]`, Rails rake/runner, IHP Scripts, Spring `CommandLineRunner` | `[@@command "…"]` на функции с модульными параметрами в отдельном файле: `[%wire]` собирает `app.commands`, `App.run ~commands` запускает `main.exe seed --count 3` между `on_start` и `on_shutdown`; опции — из меток, разбор — `Kre_shared.Scalar` (без cmdliner: те же модули, что у query) | ✅ |
| 9 | IHP Jobs, Rails ActiveJob + Solid Queue, Symfony Messenger, Nest BullMQ, Spring `@Async` | `Kre.Job`: типизированные очереди (`'a queue` = имя + dto), одна таблица `kre_jobs` (`Kre.Job.table`), `FOR UPDATE SKIP LOCKED`, повторы с удвоением паузы, `dead` после `attempts`; `[@@job q]` в провайдере, воркер — хуки провайдера `Kre.Job.S`, их запускает `[%wire]`. `enqueue` идёт через `Db` и попадает в открытую транзакцию | ✅ |
| 10 | Rails timestamps и `lock_version`, JPA `@Version` и auditing, Doctrine Timestampable | `Kre_shared.Time` (RFC 3339, native и Melange, `DOUBLE` секунд в базе), `[@created_at]`, `[@updated_at]`, `[@version]` в `table`; `update` с `WHERE version = …`, 0 строк → 409 | ✅ |
| 11 | Symfony `#[MapEntity]`, Spring `DomainClassConverter`, Rails `before_action :set_cat` | параметр-сущность: `~(cat : (Cat.t[@load Cats.find]))` с сегментом `:cat` — сегмент разбирается `Cat.Id` (тип `M.t` → `M.Id`: ppx не видит типа загрузчика), `Kre.Route.load` → 404; `[@@authorize]` получает загруженную запись | ✅ |
| 12 | Rails scaffold, Nest `g resource`, Symfony `make:crud` | `kre generate controller dogs name:string age:int born:time good:bool` (шаблоны фазы 1 + поля): тип с `[@@deriving table, dto]`, DTO, сервис в памяти, контроллер, тест с примерными значениями; проект собирается и проходит тест (`test/scaffold/new.t`). SQL и страницы `.mlx` не генерируются: правило sqlgg живёт в dune проекта, а страницы зависят от роутера приложения | ✅ |
| 13 | Symfony Workflow, Rails AASM, Spring Statemachine | `[@@deriving workflow]` + `[@@transitions { pay = (function Cart -> Paid); … }]`: переходы — `function` по конструкторам (опечатка — ошибка компиляции), `transition`, `next`, `apply` (`` `Not_allowed ``), `allowed`, `sources`, `workflow_mermaid`; native и Melange (`docs/workflow.md`) | ✅ |
| 14 | Symfony Profiler, Rails dev log и Bullet, Spring `httpexchanges` | `Kre.Profiler`: middleware собирает по запросу SQL (драйверы и `Db.query` зовут `Profiler.sql`), время, статус; `/__kre/profiler` (HTML) и `.json`, пометка N+1 (≥ 3 одинаковых запроса); только `KRE_ENV=dev` | ✅ |
| 15 | Rails ActionMailer + previews, Symfony Mailer, IHP Mail | `Kre.Mail`: `t` (адресат обязателен, `Refined.Email.t`), `render` (RFC 5322, multipart, кодирование темы), провайдеры `Smtp (Config)` (без TLS) и `Outbox ()` с превью `/__kre/mail`. Письмо не в `.mlx`: серверного рендера reason-react в native нет | ✅ |
| 16 | Spring `@HttpExchange`, Nest `HttpModule`, Symfony HttpClient | `[%http_client: val … [@@get "/users/:login"]]` — сигнатура вызовов → функтор `(Config : sig val url : string val headers : … end)` поверх `Kre_client.Http`/`Wire` (`Http.request ?base`); native и Melange (`docs/http-client.md`) | ✅ |
| 17 | Ссылки на статику, проверяемые при сборке | `[%asset "logo.png"]` → `Kre_shared.Asset.t` с адресом `/assets/logo.<хеш>.png` (нет файла — ошибка сборки с подсказкой похожего имени); `[%icon "cat"]` → `Kre_shared.Icon.t`, SVG из `assets/icons/cat.svg`, вшитый при сборке; `Kre.Assets.middleware ~dir` отдаёт файлы с вечным кэшем; `Kre_client.Icon.view` рисует иконку | ✅ |

Папка `assets/` лежит в корне приложения (родитель каталога файла, как у `[%wire]`); в dune её нужно указать в `(preprocessor_deps (source_tree ../assets))`, чтобы изменение файла пересобирало ссылки. Хеш — первые 8 символов MD5 содержимого: адрес меняется вместе с файлом, поэтому кэш можно делать вечным. `Kre.Assets.middleware` отдаёт `/assets/<имя>.<хеш>.<расширение>` из каталога и проверяет, что хеш совпадает с текущим файлом (иначе 404, а не старый файл под новым именем).

Чего не берём: ActiveRecord callbacks и Doctrine lifecycle events (скрытые побочные эффекты — у нас это сервисная функция или `Events`), Symfony Flex/recipes и Spring Boot autoconfiguration (у нас `[%wire]` при сборке), Rails concerns и Symfony bundles (это модули и библиотеки dune), HATEOAS.

## Фазы и критерии приёмки

Фаза закрыта, когда её критерий выполнен в CI. Порядок внутри фазы — сверху вниз; каждая строка — отдельная задача для Claude Code с собственным PR.

### Фаза 0 — фундамент и решения (1 неделя) — выполнена

| Задача | Критерий |
| --- | --- |
| Репозиторий, dune-project, 4 opam-пакета, CI (build + test на 5.5) | `dune build @all` зелёный на пустых пакетах |
| Проверить Melange под 5.5; зафиксировать правило версий для `shared/` | решение записано в разделе «Стек» |
| Оценить typegist (бенчмарк кодека, Melange-сборка, opam-статус) | решение (а)/(б) записано в разделе dto |
| Осмотреть jsonkit: что есть из `of_json/to_json`; решить, где живут кодеки | решение записано в разделе dto |
| `Kre.Error`, `Response`, `Codec`, `Validation`, `Refined`, `Spec`, `Controller`, `run`/`app` по `.mli` из раздела Core | alcotest на каждый модуль; `Kre.App.handler []` отвечает 404 через `Error.to_response` |

### Фаза 1 — ядро, cats end-to-end (3–4 недели)

| Задача | Критерий |
| --- | --- |
| ✅ ppx `controller`: атрибуты, классификация, `Paths`/`spec`/`register`, все ошибки | cram на эталон и каждую ошибку; cats-контроллер компилируется и проходит e2e через `Dream.test` |
| ✅ ppx `dto` (базовый, `~strict`, `[@validate]`, opaque-поля через `Json.S`) | cram на вывод; e2e cats: 422 с путём поля, `~strict` |
| ✅ `Kre_shared.Refined` (String, Int, Enum, Email, Make; Regex — открытый вопрос) | схемы содержат ограничения; `of_string` работает в path/query |
| ✅ ppx `config` (+ `Kre.Config`, profiles) | `load` собирает все ошибки сразу; cram на вывод и ошибки |
| ✅ `--emit-spec`, `--emit-openapi`; `kre client` (melange + native), `kre openapi`, `kre routes` | OpenAPI cats проходит `openapi-spec-validator`; native-клиент проходит e2e по cats против живого сервера |
| ✅ `Kre_client`: `Http`, `Error`, `Wire`, `Promise` | `examples/cats/client_js`: сгенерированный клиент, собранный Melange, в node 22 против живого сервера (`NODE=` задаёт бинарь) |
| ✅ `Kre_client.Router` + `[%path]`, `search`, `params` | node: `href`, матчинг, `search` с дефолтом и ошибкой, SSR `link` и `View`; cram: `link` с неверными params не компилируется |
| ✅ `Kre.Db` (пул, транзакции) + `Kre_db_mariadb` (sqlgg traits); `table`: `schema`, `schema.sql`, `of_row` | sqlgg-запросы против сгенерированного `schema.sql` компилируются и выполняются на MariaDB 11.8 (алиас `@db`, отдельная CI-задача) |
| ✅ `kre migrate up/down/status/new` (+ `Kre.Migration`) | e2e на MariaDB: пустая база → up → down, программно и через CLI |
| ✅ `kre new`, `kre generate controller/service/dto` | cram (`test/scaffold/new.t`) с установленными пакетами: проект собирается и проходит свой тест; ресурс из `generate controller` собирается и проходит CRUD-тест; существующие файлы не перезаписываются |
| ✅ Docs: главы Overview + Fundamentals + Validation/Serialization/Configuration + Data (+ OpenAPI/CLI, клиент) | 24 главы в `docs/`; код в них — файлы `examples/cats` и `docs/examples`, mdx (`$MDX file=`) сверяет текст с файлами, а `docs/examples/test` гоняет примеры глав через `Dream.test` |

**Критерий фазы 1:** `examples/cats` — порт Nest-примера — собирается (`dune build @all`), `dune test` зелёный, `kre client` регенерирует клиент без диффа, страница `/cats/1` в браузере показывает кота из БД.

**Статус (фаза 1 закрыта, кроме ручной проверки в браузере).** `dune build @all` и `dune test` зелёные (`NODE=` для Melange-тестов), `@db` зелёный на MariaDB 11.8; клиент генерируется dune-правилом из `spec.json`, поэтому расхождения с контроллером не бывает. Веб-часть: `examples/cats/web` собирает страницу в ES-модули (React из esm.sh через import map, без бандлера), `bin/web.ml` отдаёт `/static/**` и `page.html` на GET с `Accept: text/html`, остальное — API. С `DATABASE_URL` сервер берёт `Cats_db_service`, применяет миграции на старте; `curl` подтверждает HTML на `/cats/1` для браузера и JSON с котом из базы для `fetch`. Открыть страницу в браузере руками ещё не проверено:

```
SESSION_SECRET=dev DATABASE_URL=mariadb://user:pass@127.0.0.1/cats dune exec examples/cats/bin/main.exe
open http://localhost:8080/cats/1
```

### Фаза 2 — реальное приложение (4–6 недель)

`[@@sse]` и `[@@@gateway]`/`[@@subscribe]` для websockets с типами из shared; `[@@cron]`; `Events` (типизированная шина); `[@@cache]`; `table` CRUD; `dto` mapped types (`~partial_of`, `~pick_of`); auth-стратегии (session, JWT) + `Auth.role`; helmet/CORS/rate-limit middleware; `[@@@version]`; docstrings → OpenAPI; `Kre_db_pgx`. Критерий: главы Security, HTTP, WebSockets, Events, Task scheduling, Caching закрыты.

**Статус фазы 2** (по мере работы):
- ✅ `[@@header]`, `[@@redirect]`, `[@@timeout]`, `[@@@error_handler]`
- ✅ `[@@transactional]` + `[@from Db.tx]`, `[@@authorize]`; затем транзакция как в Spring: `with_conn`/`transaction` внутри открытой присоединяются к ней, `[@@transactional]` хватает зависимости `Kre.Db.S`
- ✅ helmet/CORS/rate-limit: `Kre.Secure_headers`, `Kre.Cors`, `Kre.Rate_limit` (`docs/security.md`)
- ✅ `[@@sse]`: тип `T.t Lwt_stream.t Lwt.t` и атрибут обязаны идти вместе; `Kre.Route.events` с явным модулем — GADT-конструктор с `'a Lwt_stream.t` невозможен (тип не инъективен); `kre client` пока пропускает такие маршруты (подписка — `EventSource`)
- ✅ WebSocket: `Kre.Gateway` (кадры `{event, data}` как в Nest, `on`/`notify` с явными модулями тела и ответа, `send`/`broadcast`, ошибки — событие `error` с Problem Details), ppx `[@@@gateway "chat"]` + `[@@subscribe "event"]`, `[%wire]` видит шлюзы; проверено живым WebSocket из node 22
- ✅ Actuator: `Kre.Actuator.make` (`/health`, `/info`, `/env`, `/routes`, `/openapi.json`, `/metrics`), `[@@health]` в провайдерах, `Config.pairs` из деривера (`docs/actuator.md`)
- ✅ кэш: `[@@cache ttl]` (ответ GET по URL, `X-Cache`), `Kre.Cache.memoize` (`find`/`evict`/`clear`) (`docs/caching.md`)
- ✅ расписание: `[@@cron]` (`Kre_shared.Cron` разбирается в ppx при сборке, `next` без `Unix` — работает и в Melange), `[@@interval]`, `[@@after]`; `Kre.Schedule`, запуск/остановка через `Kre.Wiring` (`docs/task-scheduling.md`)
- ✅ события: `Kre.Events` (`'a topic` с `Type.Id`, шина `Make ()` как провайдер), `[@@on_event]` в провайдере, подписку генерирует `[%wire]` (`docs/events.md`, `examples/events`)
- ✅ serialization: `[@exclude]` (writeOnly), `[@transform f]`, mapped types `~partial_of`/`~pick_of`/`~omit_of` с функциями `<x>_of_<t>` и `<x>_apply` (типы того же файла)
- ✅ страница Controllers: `[@@head]`, `[@@options]`, `[@@all]`, маска `*` + `[@wildcard]`, HEAD через GET, `[@@@host]` + `[@host_param]`
- ✅ `Kre_shared.Id.Make ()`: типизированные идентификаторы сущностей (`Cat.Id.t`)
- ✅ interceptors: `Kre.Interceptor.t` (полиморфный `around` над типизированным результатом), `[@@intercept]`/`[@@@intercept]`, готовые `logging`, `timeout`, `map_error`, `tap`, `chain`
- ✅ декораторы параметров Nest/Spring: `[@param]`, `[@query]`, `[@body]`, `[@header]`, `[@cookie]`, `[@signed_cookie]`, `[@session]`, `[@headers]`, `[@cookies]`, `[@ip]`, `[@host]`, `[@req]` (`Kre.Extract`), заголовки и cookies в spec/OpenAPI, заголовки в клиенте
- ✅ DI при сборке: `[%wire]`, провайдеры по форме модуля, `[@@@primary]`, выбор по имени параметра, хуки, ошибки сборки (см. «Проводка»)
- ✅ table CRUD: `Kre.Table.crud` → `crud.sql` → sqlgg `Cats_crud` (`all`/`insert`/`find`/`update`/`delete`), `for_insert`/`for_update` (`docs/data.md`)
- ✅ live loaders: `Kre.Live` (шина в памяти, `publish`/`subscribe`, канал `/__kre/live`), драйвер сообщает SQL (`read`/`wrote`), `Db.transaction` держит изменения до commit, `[@@live]` → `spec.live` + `x-kre-live` + `Cats_client.Live`, `Router.child ~live`, проверка списка при `KRE_ENV=test` (`docs/live.md`). Метаданных `reads`/`writes` sqlgg не даёт — таблицы берутся из текста SQL в traits
- ✅ PostgreSQL: `kre-db-postgresql` (libpq, не pgx — см. «Kre.Db»), `Kre.Table.schema` с диалектом, `examples/cats/postgresql` + CI-job с postgres:17
- ✅ `examples/shelter` — критерий приёмки фазы 2: всё вместе на MariaDB + node (см. «Пример приложения целиком»); `[@@deriving dto]` на варианте без аргументов даёт скаляр
- ✅ auth: `Kre.Jwt` (HS256, `sign`/`verify`/`bearer`, ошибки `` `Jwt of Malformed | Bad_signature | Expired ``), `Kre.Guard.session/map/check/optional`; роли — `Guard.check` в тип-доказательство (`docs/authentication.md`)

### Фаза 3 — экосистема

Заимствования из Rails/Symfony/Spring/Nest/IHP — таблица «Заимствования из Rails, Symfony…», по волнам. `kre migrate diff`; queues; GraphQL code-first; resilience/idempotency/outbox; i18n; file storage; microservice-транспорты. Приоритизируется по первому реальному проекту на Kre.

### Карта глав docs.nestjs.com

| Раздел Nest | Статус в Kre |
| --- | --- |
| Overview (10 глав) | фаза 1; Custom decorators = `[@from]` |
| Fundamentals | фаза 1; Circular dependency, Module reference, Discovery, Lazy-loading, Platform agnosticism — одна страница «не нужно и почему» |
| Application | Configuration/Validation/Serialization/Logging — фаза 1; Events/Task scheduling — 2; Queues/i18n/Mail/File storage — 3 |
| Data | одна глава (sqlgg + table + миграции) — фаза 1; Caching — 2; MongoDB — нет |
| Security | фаза 2 |
| HTTP | Cookies/Session/Upload/Compression/MVC — фаза 1 (Dream); Versioning/SSE/Webhooks — 2 |
| Observability | OpenTelemetry через ocaml-opentelemetry — фаза 2; остальное — нет |
| Reliability | Health checks — 2; остальное — 3 |
| GraphQL, Microservices | фаза 3 |
| WebSockets | фаза 2 |
| Standalone apps, CLI, OpenAPI | фаза 1 |
| Recipes | REPL = utop, Hot reload = dune -w, Serve static = Dream.static, Commander = cmdliner, CRUD generator = `kre generate`; CQRS — 3 |

## Конвенции для разработки и открытые вопросы

Эти правила — для `CLAUDE.md` репозитория; они перекрывают любые умолчания.

### Код

- OCaml 5.5, `(lang dune 3.23)`, ocamlformat 0.29 с профилем `default`; CI падает на неотформатированном коде.
- Минимум кода, никаких функций ради одного вызова. Illegal states unrepresentable: `option`/`result`/варианты вместо флагов и проверок. Никаких `assert false`, `failwith` в библиотечном коде, `Obj.magic`.
- Каждый публичный модуль имеет `.mli`; `Kre.*` — ровно сигнатуры из раздела Core; изменение сигнатуры — правка этого документа в том же PR.
- Сгенерированный ppx-код содержит только вызовы `Kre.Route`/`Kre_shared.Json`/`Kre_shared.Scalar`, без логики; логика — в рантайме, где её можно тестировать без ppx.
- Modular explicits — только в `server/` и `bin/`; `shared/` и `client/` — синтаксис, который собирает Melange.
- Dream не оборачивается: `Dream.request`, `Dream.middleware`, `Dream.response` в публичных сигнатурах Kre допустимы и желательны.

### ppx

- Один драйвер `kre.ppx` (`ppxlib` ≥ 0.38); трансформации регистрируются по одной, каждая — свой файл и свой набор expect-тестов.
- Все ошибки — `Location.raise_errorf` с локацией на виновный узел и текстом вида «что не так → что сделать»: ` handler find_one: missing return type annotation; add  `: Cat.t Lwt.t\`».
- Никаких предупреждений вместо ошибок; никакой «догадки» по умолчанию, если аннотация отсутствует.
- Сгенерированные имена с префиксом `__kre_`; пользовательские имена не затеняются.

### Тесты и docs

- Для каждой трансформации: expect-тест эталонного вывода + по тесту на каждую ошибку.
- `examples/cats` — всегда зелёный; это интеграционный тест ядра.
- Главы в `docs/` повторяют оглавление Nest; каждая содержит порт Nest-примера. Код в главе — не текст, а ссылка `<!-- $MDX file=… -->` на собираемый файл (`examples/` или `docs/examples/`); `dune test` падает, если текст разошёлся с файлом, `dune promote` обновляет главу. Блоки `sh` помечаются `<!-- $MDX skip -->`. Глава без такого блока не считается написанной.

### Процесс для Claude Code

- Одна строка таблицы фазы = один PR с тестами. Начинать с фазы 0 по порядку; фазу 1 — с ppx `controller`.
- Перед реализацией раздела перечитать его в этом документе; если дизайн не сходится с реальностью (версия библиотеки, невозможность в ppx), сначала правка документа с обоснованием, потом код.
- Не расширять скоуп фазы: идея, не вошедшая в таблицу, записывается в «Открытые вопросы».

### Открытые вопросы

- [x] Melange под OCaml 5.5: есть `melange.7.0.1-55`; один switch, синтаксис 5.5 разрешён везде (фаза 0).
- [x] typegist: вариант (б), не используется (фаза 0, раздел dto).
- [x] jsonkit: `of_json`/`to_json`/`t_jsonschema` есть на обоих бэкендах; `Json.S` повторяет их форму (фаза 0, раздел dto).
- [ ] jsonkit: режим декодирования с накоплением ошибок и путями (`["age"]`) — нужен для аппликативных 422; до него — первая ошибка без пути.
- [ ] Регулярные выражения в `Kre_shared` (`Validation.regex`, `Refined.Regex`): `Str` есть только в native; варианты — `re` (проверить сборку в melange) или своя реализация на `Js.Re` за общим интерфейсом.
- [ ] Длина строк в `Validation.min_length`/`max_length`: `String.length` считает байты в native и UTF-16-единицы в JS; для не-ASCII нужен подсчёт code points, одинаковый на обоих концах.
- [x] sqlgg: traits берутся из `sqlgg.mariadb` (opam `sqlgg.20260721`), `Kre.Db` — пул и транзакции; `schema.sql` печатает бинарь со списком таблиц, реестр не нужен. Форк `jongleb/sqlgg` пока не требуется; если понадобятся его возможности (IR, lattice-nullability), — pin в `dune-project`.
- [ ] Имя: `Kre` — рабочее; проверить коллизии в opam перед публикацией.
- [x] `.mlx` против reason-синтаксиса для JSX: `.mlx` (диалект dune, фаза 2).
- [x] Dream: вышел `1.0.0`, зависимость `dream >= 1.0.0`.
- [ ] WebSocket: при закрытии со стороны клиента сервер получает `None` и вызывает `Dream.close_websocket`, но клиент (node 22) не получает подтверждения закрытия в течение 3 с. Сообщения ходят. Проверить на примере `k-websocket` Dream 1.0 и, если это там же, — в Dream.
- [ ] `--emit-spec` запускает composition root (`main.ml`), а он сначала грузит конфиг, поэтому сборка требует переменных окружения (в cats dune-правило ставит `SESSION_SECRET=unused`). `spec` статичен; вариант — `kre` сам собирает маленький бинарь, который печатает `Cats_controller.spec`, без запуска `main`.
- [ ] `ssl 0.8.0`, собранный против OpenSSL 4, падает при инициализации `conduit-lwt-unix` (минимум SSL3 больше не поддерживается), а с ним и native-клиент на cohttp. Локальный switch пересобран против `openssl@3` (`PKG_CONFIG_PATH=$(brew --prefix openssl@3)/lib/pkgconfig opam reinstall ssl`); на ubuntu в CI OpenSSL 3. Чинить в ssl или уйти с conduit в native-клиенте.
- [x] Атрибуты контроллера, отложенные из фазы 1: сделаны в фазе 2, кроме `[@@sse]` (своя строка); `[@@@inject]` и `[@codec e]` не нужны (см. раздел ppx: controller).

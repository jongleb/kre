# Forge — дизайн NestJS-подобного фреймворка на OCaml

Oct 31, 2026 · @Mr

## Цель и принципы

Forge — фуллстек-фреймворк на OCaml, который воспроизводит структуру и главы [docs.nestjs.com](https://docs.nestjs.com/) средствами OCaml 5.5: сервер на Dream, фронтенд на Melange, общий код в `shared/`. Документация Forge повторяет оглавление Nest глава в главу; глава считается закрытой, когда её примеры из Nest переписаны на Forge и компилируются.

Принципы, которые решают спорные вопросы при разработке:

1. **Не воспроизводить то, что в OCaml уже есть.** Nest-овские `@Module`, DI-контейнер, `forwardRef`, Discovery, Module reference — это компенсация отсутствия модульной системы в TS. У нас модуль = singleton-провайдер, `.mli` = exports, `main.ml` = composition root, зависимости = module-dependent functions (modular explicits, OCaml 5.5). Разрешение зависимостей — на этапе компиляции, а не старта.
2. **ppx только там, где нужен рефлекшн.** Маршруты из сигнатур хендлеров, кодеки и валидация DTO, конфиг из env, типизированные пути на фронте. Всё остальное — обычные функции и модули.
3. **Dream не оборачиваем.** `Dream.request`, `Dream.middleware`, `Dream.response`, сессии, CSRF, websockets, static — используются напрямую. Forge добавляет слой выше, не прячет слой ниже.
4. **Контроллер — источник правды.** Из него (через `spec`) генерируются типизированный Melange-клиент и OpenAPI. Контракт нигде не дублируется руками.
5. **Один синтаксис для сервера и клиента.** Пользовательский код на обоих концах читается одинаково: атрибуты на `let`, `[@@deriving …]` на типах.
6. **Illegal states unrepresentable, минимум кода.** Никаких `assert false`, никаких `Obj.magic`, ошибки ppx — через `Location.raise_errorf` с текстом, объясняющим, что исправить.

Не делаем в первых фазах: ORM (вместо него sqlgg + `table`), GraphQL, microservices/transporters, queues, MongoDB, platform-agnosticism (только Dream), Devtools-граф, Observability-SaaS.

## Стек и версии

Сервер и клиент — OCaml 5.5.1 в одном opam-switch: Melange `7.0.1-55` собран под 5.5, modular explicits компилируются и в native, и в JS (проверено в фазе 0).

| Компонент | Версия / выбор | Зачем |
| --- | --- | --- |
| OCaml | 5.5.0 ([релиз 19 июня 2026](https://ocaml.org/changelog/2026-06-19-ocaml-550)) | modular explicits `(module M : S) -> …`, полиморфные параметры, GC |
| ppxlib | ≥ 0.38.0 (в switch — 0.39.0) | все ppx Forge |
| dune | ≥ 3.21 (в switch — 3.24) | `(modes :standard melange)` для shared, `melange.emit` |
| Dream | 1.0.0 | HTTP, sessions, CSRF, websocket, static |
| routes | 2.0.0 | типизированные пути на обоих концах |
| Lwt + lwt\_ppx | 6.1 | монада сервера; `let%lwt`, `match%lwt` |
| Melange | 7.0.1-55 (OCaml 5.5) | фронтенд, `Js.Promise` |
| reason-react + mlx | текущие | компоненты, JSX-синтаксис в `.mlx` |
| jsonkit | собственная | JSON-тип и `[@@deriving jsonschema]`, native + melange |
| sqlgg / ppx\_sqlgg | собственный форк | типизированный SQL |
| cmdliner | текущая | CLI `forge` |
| ocamlformat | 0.29 (синтаксис 5.5) | форматирование |
| ppx\_expect + alcotest | текущие | тесты |

**Два базовых решения по библиотекам.** Весь JSON — [jsonkit](https://github.com/melange-community/jsonkit): тип `Jsonkit.t`, кодеки, `[@@deriving jsonschema]`; Forge не определяет собственного JSON-типа и не генерирует кодеков сам — чего не хватает, добавляется в jsonkit. Все пути — [routes](https://github.com/anuragsoni/routes) (anuragsoni): типизированный двунаправленный роутер, чистый OCaml, работает и в Melange; одно значение `Routes.path` даёт матчинг на сервере, `sprintf` для клиентов и `string_of_path` для OpenAPI. `Dream.router` со строковыми паттернами не используется; `Forge.App.handler` матчит через `Routes.one_of`/`Routes.match'` и остаётся обычным `Dream.handler`.

**Правило про версии компилятора (решено в фазе 0).** Melange 7.0.1-55 поддерживает OCaml 5.5, поэтому отдельный switch для клиента не нужен, а синтаксис 5.5 (modular explicits) разрешён везде, включая `shared/` и `client/`. `dune-project` требует `ocaml >= 5.5 & < 5.6`; локальный switch проекта — `opam switch create . 5.5.1`.

**Монады.** Сервер — `Lwt.t`; клиент — `Js.Promise.t` (обёртка `Forge_client.Promise` с `let*`). Ни один тип в `shared/` не упоминает монаду: контракт между концами — только данные (DTO) и `spec`.

**Lwt-конвенции.** Пользовательский код — `lwt_ppx` (`let%lwt`, `match%lwt`, `try%lwt`); сгенерированный ppx-код — `Lwt_result.Syntax` (`let*` над `('a, Error.t) result Lwt.t`), без `lwt_ppx`, чтобы `forge.ppx` не зависел от порядка применения препроцессоров. Исключения в хендлерах ловятся в `Forge.Route.handle` через `Lwt.catch`, не через `try%lwt` в сгенерированном коде. Жизненный цикл — `Lwt_switch` (`run ~on_shutdown` вешает на него). Таймаут на хендлер — `[@@timeout 5.0]` → `Lwt.pick` с `Lwt_unix.sleep`, по умолчанию выключен. Eio и `Lwt_eio` не используются; переход на effects — только вместе с заменой Dream, через тот же `Forge.Route.handle`.

**Многоядерность.** Dream однодоменный. Горизонтальное масштабирование — N процессов за балансировщиком; `Forge.App.run ~domains` не планируется.

## Структура репозитория и пакеты

Один монорепозиторий `forge`, четыре opam-пакета. Пример `examples/cats` — порт примера из Nest-доков и одновременно интеграционный тест.

```
forge/
  dune-project
  forge.opam          # forge.shared (Forge_shared, native + melange) и forge (Forge, рантайм сервера, native)
  forge-ppx.opam      # ppx: controller, dto, config, table
  forge-client.opam   # Forge_client: Http, Router, Path, Search + ppx search/params/path (melange)
  forge-cli.opam      # бинарь forge
  src/
    shared/           # Forge_shared: Validation, Codec, Json, Refined — собирается в обоих режимах
    core/             # Forge: Error, Response, Guard, Spec, Route, Controller, App
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
    ppx/              # ppx_expect-тесты на -dsource вывод каждой трансформации
    core/             # alcotest: Error.handler, Codec, Validation, Spec→OpenAPI
    e2e/              # поднимает examples/cats, дёргает Dream.test и сгенерированный клиент
  docs/               # зеркало оглавления docs.nestjs.com, по файлу на главу
```

Правила зависимостей между пакетами:

- `forge.shared` зависит только от jsonkit (native) / jsonkit-melange (melange); Dream и Lwt не видит.
- `forge` зависит от `forge.shared`, Dream, Lwt, routes, jsonkit; не зависит от ppx.
- `forge-ppx` зависит от ppxlib и jsonkit (для `dto`); генерируемый код ссылается только на `Forge.*`, `Forge_shared.*` и `Jsonkit.*`.
- `forge-client` зависит от melange, reason-react, jsonkit-melange, `forge.shared`; не зависит от `forge`.
- `shared/` пользовательского проекта зависит только от jsonkit и `forge.shared` (+ `forge-ppx` для `dto`), собирается в обоих режимах.

Модульные имена: `Forge_shared` (общие для обоих концов: `Forge_shared.Refined`, `Forge_shared.Codec`, …), `Forge` (сервер: `Forge.Error`, `Forge.App`, …), `Forge_client`, `Forge_ppx` (не экспортируется пользователю). Разделение — решение фазы 0: `shared/` собирается в Melange и не может зависеть от серверной библиотеки, которая тянет Dream. Ре-экспорт `Forge_shared` из `Forge` не делается (правило «никаких алиасов»).

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
module Name  = Forge_shared.Refined.String (struct let name = "name"  let min = 1 let max = 64 end)
module Age   = Forge_shared.Refined.Int    (struct let name = "age"   let min = 0 let max = 40 end)
module Breed = Forge_shared.Refined.Enum   (struct let name = "breed" let values = [ "siamese"; "persian"; "maine coon" ] end)

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

open Forge

let find_all (module Cats : Cats_service.S) ?(limit = 20) () : Cat.t list Lwt.t =
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
  Forge.App.run ~port:config.port
    ~middleware:[ Dream.logger ]
    [ Cats_controller.register (module Cats_service) ]
```

**client/gen/cats\_client.ml** — генерируется командой `forge client` из `spec` сервера:

```ocaml
val find_all : ?limit:int -> unit -> (Cat.t list, Forge_client.Error.t) result Promise.t
val find_one : id:int -> (Cat.t, Forge_client.Error.t) result Promise.t
val create   : body:Create_cat_dto.t -> (Cat.t, Forge_client.Error.t) result Promise.t
(* параметр user с [@guard] в клиент не попадает *)
```

**client/routes.ml** — typed router:

```ocaml
open Forge_client.Router

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
  shared/   user.ml  cat.ml  adoption.ml  login_dto.ml  create_cat_dto.ml  adopt_dto.ml
  server/   config.ml  auth.ml  users_service.ml  cats_service.ml  adoptions_service.ml
            auth_controller.ml  cats_controller.ml  adoptions_controller.ml
            queries/cats.sql  queries/users.sql  migrations/0001_init.sql
  client/   routes.ml  pages/cats_index.mlx  pages/cat_show.mlx  pages/login.mlx  gen/*_client.ml
  bin/      main.ml
```

### shared — типы, одни на оба конца

```ocaml
(* user.ml *)
module Email = Forge_shared.Refined.Email
type role = Admin | Member [@@deriving dto]
type t = {
  id    : int;     [@primary] [@auto]
  email : Email.t; [@unique]
  role  : role;    [@default Member]
} [@@deriving table ~name:"users", dto]
(* table под melange ничего не эмитит; dto — и там, и там *)

(* cat.ml *)
module Name = Forge_shared.Refined.String (struct let name = "name" let min = 1 let max = 64 end)
module Age  = Forge_shared.Refined.Int    (struct let name = "age"  let min = 0 let max = 40 end)
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
  env            : string; [@env "FORGE_ENV"] [@default "dev"]
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
module Make (Db : Forge.Db.S) : S = struct
  let find id = Db.with_conn (fun c -> Users_sql.by_id c ~id >|= Option.map User.of_row)
  let verify ~email ~password =
    Db.with_conn (fun c ->
      let%lwt row = Users_sql.by_email c ~email:(User.Email.to_repr email) in
      Lwt.return (Option.bind row (fun r -> if Argon2.verify r.password_hash password then Some (User.of_row r) else None)))
end

(* cats_service.ml — Forge.Db.conn один для всех драйверов, поэтому сигнатура не зависит от Db *)
module type S = sig
  val available : unit -> Cat.t list Lwt.t
  val find      : int -> Cat.t option Lwt.t
  val create    : Create_cat_dto.t -> Cat.t Lwt.t
  val owner_of  : int -> int option Lwt.t
  val adopt     : conn:Forge.Db.conn -> cat:int -> user:int -> (unit, Forge.Error.t) result Lwt.t
end
module Make (Db : Forge.Db.S) : S = struct
  let available () = Db.with_conn (fun c -> Cats_sql.available c >|= List.map Cat.of_row)
  let find id = Db.with_conn (fun c -> Cats_sql.by_id c ~id >|= Option.map Cat.of_row)
  let create (d : Create_cat_dto.t) =
    Db.with_conn (fun c -> Cat.insert c { Cat.id = 0; name = d.name; age = d.age; status = Available; owner_id = None })
  let owner_of id = find id >|= Option.bind ~f:(fun c -> c.Cat.owner_id)
  let adopt ~conn ~cat ~user =
    let%lwt n = Cats_sql.adopt conn ~id:cat ~user_id:user in
    Lwt.return (if n = 1 then Ok () else Error (Forge.Error.conflict "cat is not available"))
end

(* adoptions_service.ml — зависимость от другого сервиса = функторный параметр *)
module type S = sig
  val adopt : conn:Forge.Db.conn -> cat:int -> user:int -> (Adoption.t, Forge.Error.t) result Lwt.t
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

let current : User.t Forge.Guard.t = Forge.Guard.field user_field ~missing:(Forge.Error.unauthorized "login required")
let admin   : unit Forge.Guard.t   = fun req ->
  current req >|= Result.bind ~f:(fun u -> if u.User.role = Admin then Ok () else Error (Forge.Error.forbidden "admin only"))
```

### server — контроллеры

```ocaml
(* auth_controller.ml *)
[@@@controller "auth"]

let login (module Users : Users_service.S) (req : Dream.request) ~(body : Login_dto.t)
    : (User.t, Forge.Error.t) result Lwt.t =
  match%lwt Users.verify ~email:body.email ~password:body.password with
  | None -> Lwt.return_error (Forge.Error.unauthorized "bad credentials")
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

let show (module Cats : Cats_service.S) ~(id : int) : (Cat.t, Forge.Error.t) result Lwt.t =
  Cats.find id >|= Option.to_result ~none:(Forge.Error.not_found "cat")
[@@get ":id"]

let create (module Cats : Cats_service.S) ~(body : Create_cat_dto.t) : Cat.t Lwt.t = Cats.create body
[@@post] [@@status 201] [@@guards [Auth.admin]]

let rename (module Cats : Cats_service.S)
    ~(user : User.t [@guard Auth.current]) ~(id : int) ~(body : Create_cat_dto.t)
    : (Cat.t, Forge.Error.t) result Lwt.t = …
[@@put ":id"]
[@@authorize fun ~user ~id -> Cats.owner_of id >|= fun o -> user.role = Admin || o = Some user.id]

(* adoptions_controller.ml *)
[@@@controller "adoptions"]

let adopt (module Adoptions : Adoptions_service.S)
    ~(user : User.t [@guard Auth.current])
    ~(conn : Forge.Db.conn [@from Forge.Db.tx])
    ~(body : Adopt_dto.t) : (Adoption.t, Forge.Error.t) result Lwt.t =
  Adoptions.adopt ~conn ~cat:body.cat_id ~user:user.id
[@@post] [@@status 201] [@@transactional]
(* Error → rollback + 409; Ok → commit + Live.publish "cats" и "adoptions" (из writes sqlgg/table) *)
```

### bin/main.ml — весь composition root

```ocaml
let () =
  let config = Config.load_exn () in
  let module Db = Forge.Db.Make (Forge_db_mariadb) (struct let url = config.db_url let pool = 8 end) in
  let module Users = Users_service.Make (Db) in
  let module Cats = Cats_service.Make (Db) in
  let module Adoptions = Adoptions_service.Make (Cats) in
  Forge.App.run ~port:config.port
    ~middleware:[ Dream.logger; Dream.cookie_sessions ~secret:config.session_secret; Auth.session (module Users) ]
    [ Auth_controller.register (module Users);
      Cats_controller.register (module Cats);
      Adoptions_controller.register (module Adoptions);
      Forge.Actuator.routes ~config:(Config.pp config) () ]
```

Забыли `(module Users)` — не компилируется. Переименовали `Cat.name` — не компилируются `cats.sql` (через `schema.sql`), `Create_cat_dto`, клиент, страницы.

### client

```ocaml
(* routes.ml *)
open Forge_client.Router
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
         | Error e -> Toast.error (Forge_client.Error.message e))
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

## Forge.Core — рантайм сервера

Сигнатуры ниже — `.mli` из `src/shared` и `src/core` в том виде, в каком они собраны в фазе 0; ppx генерирует код только против них. Всё, чего здесь нет, в рантайм не попадает без правки этого раздела.

### Forge\_shared — общий для сервера и клиента (native + melange)

```ocaml
(* Forge_shared.Validation — ошибки и правила; Nest: class-validator *)
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
  val min_length : int -> string rule   val max_length : int -> string rule
  val min : int -> int rule             val max : int -> int rule
  val range : min:int -> max:int -> int rule
  val one_of : string list -> string rule
  val email : string rule
end

(* Forge_shared.Json — форма, которую даёт [@@deriving json, jsonschema] из jsonkit *)
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

(* Forge_shared.Scalar — значение, которое живёт и в JSON, и в сегменте пути/query; Nest: ParseIntPipe *)
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

`Forge_shared.Refined` — см. раздел dto.

### Forge — сервер (native)

```ocaml
(* Forge.Error — единый тип ошибок; Nest: HttpException + exception filters *)
module Error : sig
  type status = [ Dream.client_error | Dream.server_error | `Unprocessable_Entity ]
  type t = private {
    status : status; code : string; type_ : string; detail : string;
    extensions : (string * Jsonkit.t) list;   (* доп. члены Problem Details верхнего уровня *)
  }
  exception E of t
  val make : status:status -> code:string -> ?type_:string -> ?extensions:(string * Jsonkit.t) list -> string -> t
  val bad_request : ?extensions:(string * Jsonkit.t) list -> string -> t   (* 400 *)
  val unauthorized : string -> t      (* 401 *)
  val forbidden : string -> t         (* 403 *)
  val not_found : string -> t         (* 404 *)
  val conflict : string -> t          (* 409 *)
  val unprocessable : Forge_shared.Validation.t -> t   (* 422, extensions.errors *)
  val internal : string -> t          (* 500 *)
  val to_json : instance:string -> t -> Jsonkit.t      (* RFC 9457 *)
  val to_response : Dream.request -> t -> Dream.response Lwt.t
  val fail : t -> 'a Lwt.t
end

(* Forge.Response — явный JSON-ответ; остальное (text, html, redirect, stream) — сам Dream *)
module Response : sig
  val json : ?status:Dream.status -> (module J : Forge_shared.Json.S) -> J.t -> Dream.response Lwt.t
end

(* Forge.Guard — извлечение значения из запроса; Nest: guards + custom param decorators *)
module Guard : sig
  type 'a t = Dream.request -> ('a, Error.t) result Lwt.t
  val field : 'a Dream.field -> missing:Error.t -> 'a t
  val header : string -> string t
  val both : 'a t -> 'b t -> ('a * 'b) t
end

(* Forge.Spec — рантайм-описание контроллера; источник для forge client / forge openapi *)
module Spec : sig
  type verb = [ `GET | `POST | `PUT | `PATCH | `DELETE ]
  type presence = Required | Optional | Repeated
  type location = Path | Query of presence     (* path-параметр не бывает необязательным *)
  type dto = { name : string; schema : Jsonkit.Jsonschema.t }
  type param = { name : string; location : location; scalar : string; schema : Jsonkit.Jsonschema.t }
  type returns = Unit | Text | Json of dto | Raw
  type route = {
    verb : verb; path : string; name : string; params : param list;
    body : dto option; returns : returns; status : Dream.status; guards : string list;
  }
  type t = { prefix : string; version : int option; routes : route list }
  val to_json : t -> Jsonkit.t
end

(* Forge.Route — то, во что ppx превращает хендлер; логика здесь, не в сгенерированном коде *)
module Route : sig
  type handler = Dream.request -> (Dream.response, Error.t) result Lwt.t
  type t = private { verb : Spec.verb; middleware : Dream.middleware list; target : handler Routes.route }
  type 'a returns =
    | Unit : unit returns
    | Text : string returns
    | Json : (module Forge_shared.Json.S with type t = 'a) -> 'a returns
    | Found : (module Forge_shared.Json.S with type t = 'a) -> 'a option returns   (* None → 404 *)
    | Raw : Dream.response returns
  val v : ?middleware:Dream.middleware list -> Spec.verb -> handler Routes.route -> t
  val handle : status:Dream.status -> ?guards:unit Guard.t list -> 'a returns ->
    (Dream.request -> ('a, Error.t) result Lwt.t) -> handler
end

(* Forge.Controller *)
module Controller : sig
  type t = private { spec : Spec.t; middleware : Dream.middleware list; routes : Route.t list }
  val v : ?middleware:Dream.middleware list -> spec:Spec.t -> Route.t list -> t
end

(* Forge.App — сборка и запуск *)
module App : sig
  type tls = Development_certificate | Certificate of { certificate_file : string; key_file : string }
  type error_handler = Dream.request -> Error.t -> Dream.response Lwt.t
  val handler : ?middleware:Dream.middleware list -> ?error_handler:error_handler -> Controller.t list -> Dream.handler
  val run : ?interface:string -> ?port:int -> ?tls:tls -> ?middleware:Dream.middleware list ->
    ?error_handler:error_handler -> ?on_start:(unit -> unit Lwt.t) -> ?on_shutdown:(unit -> unit Lwt.t) ->
    Controller.t list -> unit
end
```

Отклонения от первой версии этого раздела (фаза 0) и почему:

- `Forge.run`/`Forge.app` → `Forge.App.run`/`Forge.App.handler`: обёрточный модуль dune не может содержать значения без ре-экспорта подмодулей алиасами, а алиасы запрещены.
- `Codec.t` (запись) → модули `Forge_shared.Scalar.S`: одна сущность «значение в JSON и в URL», `Refined.Make` собирается через `include` без алиасов, а ppx передаёт `(module Forge_shared.Scalar.Int)` как modular explicit.
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
2. Label = `body` → **body**. Тип `T.t` → модуль `T` должен удовлетворять `Forge_shared.Json.DTO`; генерируется `T.of_json` → `T.validate` → при ошибке `Error.unprocessable`.
3. Параметр несёт `[@guard e]`/`[@from e]` → **guard**: `e req` вычисляется до тела; `Error` → ответ; в `spec` и в клиент не попадает.
4. Всё остальное labelled/optional → **query**. `?x : τ option` = необязательный; `?(x = d)` = необязательный с дефолтом; `~x` = обязательный, отсутствие → 400. `τ list` → повторяемый параметр `?x=a&x=b`.
5. Позиционный с аннотацией `Dream.request` → сырой запрос. Любой другой позиционный, кроме финального `()`, — ошибка.

Подбор кодека по типу (синтаксически, по последнему компоненту пути типа): `int → Codec.int`, `int64`, `float`, `bool`, `string`; `T.t → T.codec` (модуль обязан экспортировать `codec : t Forge_shared.Scalar.S`); `τ option` и `τ list` — обёртки. Иной тип → ошибка «unsupported param type, provide `[@codec e]`» (параметр `[@codec e]` с явным `'a Codec.t` разрешён).

### Инъекция из запроса: `[@from]` и `Forge.Extract`

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

`Forge.Extract` — стандартные извлечения, в `Core`:

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
  val params  : (string * string) list Guard.t            (* @Param() целиком *)
  val body_raw : string Guard.t
  val body_json : Jsonkit.t Guard.t                       (* @Body() без DTO *)
  val session : string -> string option Guard.t           (* Dream.session_field *)
  val field   : 'a Dream.field -> missing:Error.t -> 'a Guard.t
end
```

Свой декоратор (`createParamDecorator`) — обычное значение: `let tenant : Tenant.t Guard.t = fun req -> …`. Комбинаторы в `Guard`: `map`, `both`, `optional : 'a t -> 'a option t`, `with_default`. `@Res()` аналога нет намеренно: ответ — возвращаемое значение, а для полного контроля есть `Response.t Lwt.t`.

### Тип возврата

Распознаваемые формы аннотации (`τ` — тип данных, `E` = `Forge.Error.t`):

| Аннотация | Сериализация | `Spec.returns` |
| --- | --- | --- |
| `unit Lwt.t` | пустой ответ, статус по умолчанию 204 | `Unit` |
| `string Lwt.t` | `text/plain` | `Text` |
| `T.t Lwt.t` | `T.to_json`, `application/json` | `Json ("T", T.jsonschema)` |
| `T.t list Lwt.t`, `T.t option Lwt.t` | JSON-массив / JSON или 404 | `Json` с обёрткой в схеме |
| `(τ, E) result Lwt.t` | как τ; `Error e` → `error_handler` | как τ |
| `Forge.Response.t Lwt.t`, `Dream.response Lwt.t` | как есть | `Raw` |
| `τ Lwt_stream.t Lwt.t` + `[@@sse]` | `text/event-stream`, элементы через `T.to_json` | `Json` + `sse = true` |

Не-`Lwt` возврат — ошибка «handler must return … Lwt.t». Аннотация, не подпадающая под таблицу, — ошибка с перечислением форм.

### Зависимости (modular explicits)

Модульные параметры всех хендлеров объединяются по имени. Одно имя с разными сигнатурами (текстуально) — ошибка. Объединённый список становится параметрами `register`, в том порядке, в котором имена впервые встретились в файле. Внутри сгенерированного функтора параметры хендлеров удаляются, тело ссылается на функторные модули.

### Что генерируется

Для файла с префиксом `"cats"` и зависимостями `Cats : Cats_service.S`:

```ocaml
module Make (Cats : Cats_service.S) = struct
  (* все не-хендлерные items файла как есть *)
  let find_one ~id = …                          (* тело хендлера без модульных параметров *)

  (* путь — значение routes; из "cats" + ":id" и типа ~id:int ppx строит: *)
  let __forge_path_find_one = Routes.(s "cats" / int /? nil)

  let __forge_route_find_one =
    Routes.(__forge_path_find_one @--> fun id ->
      Forge.Route.handle ~verb:`GET ~status:200 ~guards:[]
        ~result:(Forge.Route.Json (module Cat))
        (fun _req -> find_one ~id))

  let routes : Forge.Route.t list = [ __forge_route_find_all; __forge_route_find_one; __forge_route_create ]
end

(* пути экспортируются и наружу — для тестов, ссылок и клиента *)
module Paths = struct
  let find_one = Routes.(s "cats" / int /? nil)     (* : (int -> 'a, 'a) Routes.path *)
  …
end

let spec : Forge.Spec.t = { prefix = "/cats"; version = None; routes = [ … ] }

let register (module Cats : Cats_service.S) : Forge.Controller.t =
  let module M = Make (Cats) in
  Forge.Controller.v ~spec ~routes:M.routes ~middleware:[ Logger_middleware.use ] ()
```

Путь и параметры: из строки `[@@get ":id"]` и типов path-параметров ppx собирает `Routes.path` — `int → Routes.int`, `int64`, `string → str`, `T.t → Routes.pattern T.codec.to_string T.codec.of_string_opt ":name"`. Хендлер получает path-параметры в порядке их появления в пути, что совпадает с типом `(int -> 'a, 'a) Routes.path`. `Forge.Route.t` — `Dream.handler Routes.route` с привязанным методом; `Forge.App.handler` собирает все контроллеры в один `Routes.one_of` на метод и матчит `Dream.target`. `MatchWithTrailingSlash` → 301 на путь без слеша (настраивается в `run ~trailing_slash`). `Paths` даёт тестам и серверному коду `Routes.sprintf Cats_controller.Paths.find_one 42 = "/cats/42"` — URL нельзя написать неправильно.

`Forge.Route` — внутренний модуль рантайма: `handle` оборачивает guards, парсинг, сериализацию и маппинг ошибок; `Syntax.let*` — `Lwt_result`-bind с `Error.t`. Генерируемый код не содержит логики, только вызовы `Forge.Route`; это держит ppx маленьким и тестируемым.

### Ошибки ppx (все через `Location.raise_errorf`, с локацией на виновный узел)

- `[@@@controller]` не первый item; два `[@@@controller]` в файле.
- `[@@get]` на `let` с паттерном не-идентификатором, на `let rec`, на `and`.
- Отсутствие аннотации типа возврата; неподдерживаемая форма.
- Path-параметр из пути без соответствующего label (`":id"`, но нет `~id`), и наоборот — label совпадает с `:x`, но тип не аннотирован.
- Два параметра `body`; `body` без типа `T.t`.
- Позиционный параметр без аннотации `Dream.request`.
- Конфликт сигнатур модульного параметра.
- `[@@status]` вне 100–599; `[@@sse]` без `Lwt_stream.t`.

Каждая ошибка — отдельный ppx\_expect-тест в `test/ppx/`.

## DI и остальные примитивы Nest

Все примитивы Overview-раздела Nest выражаются без контейнера. Таблица ниже — нормативная: так, и только так, переводится каждая концепция.

| Nest | Forge | Механизм |
| --- | --- | --- |
| Provider (`@Injectable`, singleton) | модуль с `module type S` в `.mli` | состояние — top-level значения модуля |
| Provider с зависимостями | функтор `Make (Db : Db.S) (Log : Logger.S) : S` | применяется в `main.ml` |
| Constructor injection | модульные параметры хендлера `(module Cats : Cats_service.S)` | modular explicits → параметры `register` |
| `useValue` / `useClass` / `useFactory` | другой модуль того же `S`; фабрика = `let%lwt` в `main` до `Forge.App.run` | — |
| Dynamic module `forRoot(cfg)` | функтор с конфиг-модулем: `Cache.Make (struct let ttl = 60 end)` | — |
| Scope.DEFAULT | модуль | — |
| Scope.REQUEST | `Dream.field` + `Guard.field` | значение кладёт middleware, читает `[@guard]` |
| Scope.TRANSIENT | обычная функция | — |
| `@Module({imports, providers, exports})` | `main.ml` + `.mli` + dune `(libraries)` | не существует как сущность |
| Circular dependency / `forwardRef` | ошибка компиляции | — |
| Middleware | `Dream.middleware`; `[@@@use]` / `[@@use]` / `Forge.App.run ~middleware` | — |
| Middleware с зависимостями | `let use (module Log : Logger.S) : Dream.middleware = …` | применяется в `[@@@use [Logger.use (module Log)]]` |
| Guard (`canActivate`) | `'a Guard.t = Dream.request -> ('a, Error.t) result Lwt.t` | `[@guard e]` даёт значение; `[@@guards [e]]` только проверяет |
| Pipe (`ParseIntPipe`) | аннотация типа параметра | `Codec` |
| Pipe (`ValidationPipe`) | `[@@deriving dto]` → `validate` | автоматически на `body` |
| Custom pipe | `[@codec e]` на параметре / `Codec.custom` | — |
| Interceptor (before/after) | `Dream.middleware` | — |
| Interceptor (transform response) | middleware над `Dream.response` или явный `Response.json` | RxJS не вводим |
| Exception filter | `Forge.App.run ~error_handler`; на контроллер — `[@@@error_handler f]` | `Error.t -> Dream.response Lwt.t` |
| `HttpException` | `Error.t` в `result` или `Error.fail` | — |
| Custom param decorator (`@User()`) | `[@from Auth.current]` | любой `'a Guard.t` |
| Execution context | позиционный `(req : Dream.request)` | — |
| Lifecycle (`onModuleInit`, `onApplicationShutdown`) | `Forge.App.run ~on_start ~on_shutdown` | `Lwt_switch` внутри |

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

Генерирует для `type t` модуль формы `Forge_shared.Json.S` (решение фазы 0, см. «Связь с jsonkit»):

```ocaml
val of_json      : Jsonkit.t -> t      (* jsonkit [@@deriving json] + правила; бросает Validation.Invalid *)
val to_json      : t -> Jsonkit.t      (* jsonkit [@@deriving json] *)
val t_jsonschema : Jsonkit.Jsonschema.t   (* jsonkit [@@deriving jsonschema] + ограничения *)
```

На границе (тело запроса, ответ клиента) вызывается `Forge_shared.Json.parse (module T) json : (T.t, Validation.t) result`. Отдельного `validate` нет: проверка — часть разбора, и после `of_json` значение уже валидно.

Для `type foo` — те же имена с префиксом `foo_` (конвенция jsonkit: `foo_of_json`, `foo_jsonschema`).

### Рекомендуемый путь: opaque-типы (parse, don't validate)

Поле DTO должно иметь тип, в котором невалидное значение непредставимо. Тогда `of_json` — единственная точка проверки, а сервис никогда не получает «сырую» строку. `[@validate]` на `string`/`int` — допустимый escape hatch для одноразовых правил, но не основной способ.

`Forge_shared.Refined` — фабрики opaque-типов, собранные в `shared/` (реализовано в фазе 0):

```ocaml
module type S = sig
  type t
  type repr
  include Forge_shared.Scalar.S with type t := t   (* of_json/to_json/t_jsonschema + of_string/to_string: работает и в теле, и в path/query *)
  val of_repr : repr -> (t, Forge_shared.Validation.t) result   (* умный конструктор *)
  val to_repr : t -> repr
  val pp : Format.formatter -> t -> unit
end

module type RULES = sig
  type base
  val name : string                                         (* title в схеме *)
  val rules : base Forge_shared.Validation.rule list
  val constraints : (string * Jsonkit.Jsonschema.t) list    (* minLength, enum, format, … *)
end

module Make (Base : Forge_shared.Scalar.S) (C : RULES with type base := Base.t) : S with type repr = Base.t
module String (C : sig val name : string  val min : int  val max : int end) : S with type repr = string
module Int    (C : sig val name : string  val min : int  val max : int end) : S with type repr = int
module Enum   (C : sig val name : string  val values : string list end)    : S with type repr = string
module Email  : S with type repr = string
(* Regex — отложен: нужен regex-движок, работающий и в native, и в melange *)
```

Связь с `dto`: поле типа `T.t`, где `T : Json.S`, кодируется через `T.of_json`/`T.to_json`, схема — `T.t_jsonschema`. Это ровно то, что вызывает деривер jsonkit для поля типа `T.t`, поэтому opaque-модули из `Refined` встраиваются в jsonkit-записи без участия ppx. Ошибки полей должны собираться аппликативно (не fail-fast) в один `Validation.t` с путями — для этого jsonkit-декодеру нужен режим с накоплением ошибок и путями (открытый вопрос; до него — первая ошибка, путь пустой).

Кросс-полевые инварианты (пароль = подтверждение, `from < to`) — либо opaque-запись со своим `of_repr`, либо `[@@dto.check f]` на типе, `f : t -> (t, Validation.t) result`, который `of_json` вызывает последним.

### typegist — решение фазы 0: (б), не используется

[typegist](https://github.com/dbuenzli/typegist) представляет OCaml-типы как значения, поверх которых пишутся generic-кодеки. Решение — (б): `dto` не генерирует gist, а опирается на деривера jsonkit. Причины: в opam есть только `typegist.0.0.0`; принято, что весь JSON — jsonkit, а в jsonkit уже есть `[@@deriving json]` и `[@@deriving jsonschema]` на обоих бэкендах, так что `dto` сводится к тонкой надстройке (правила, `[@exclude]`, `[@expose]`), и gist дублировал бы jsonkit. Вернуться к вопросу, если понадобятся generic-производные, которых нет в jsonkit (QuickCheck-генераторы, диффы).

### Атрибуты полей

| Атрибут | Эффект | Nest-аналог |
| --- | --- | --- |
| `[@key "camelName"]` | имя в JSON | `@Expose({ name })` |
| `[@default e]` | поле необязательно в JSON, дефолт при отсутствии | `@IsOptional` + default |
| `[@validate r1; r2]` | правила `'a Forge_shared.Validation.rule`, применяются по порядку, ошибки всех правил собираются | class-validator |
| `[@validate.custom f]` | `f : t_field -> (t_field, string) result` → `Validation.rule ~name:"custom" f` | `@Validate(Custom)` |
| `[@exclude]` | не сериализуется в `to_json`; `of_json` требует `[@default]` | `@Exclude` |
| `[@expose ~groups:["admin"]]` | сериализуется только при `to_json ~groups` | `@Expose({ groups })` |
| `[@nested]` | не нужен: вложенный DTO проверяется своим `T.of_json` | `@ValidateNested` |

Правила валидации — обычные значения `Forge_shared.Validation.*`; ppx лишь вызывает их и собирает `{ path; rule; message }`. Новые правила добавляются в рантайм, а не в ppx.

### Опции деривера

| Опция | Эффект | Nest-аналог |
| --- | --- | --- |
| `[@@deriving dto]` | всё выше | — |
| `[@@deriving dto ~partial_of:T]` | тип = все поля `T.t` как `option`; `validate` применяет правила `T` к присутствующим полям | `PartialType` |
| `[@@deriving dto ~pick_of:(T, ["name"; "age"])]` / `~omit_of` | подмножество полей `T` | `PickType` / `OmitType` |
| `[@@deriving dto ~strict]` | неизвестные поля в JSON → ошибка | `forbidNonWhitelisted` |

`~partial_of`/`~pick_of` требуют, чтобы `T` был объявлен в том же файле или `T.t` был виден ppx как запись — реализуется через `[@@deriving dto]` на `T`, который дополнительно эмитит `__dto_fields_T` (список полей со схемами) для переиспользования. Это фаза 2; в фазе 1 — только базовый `dto` и `~strict`.

### Варианты

| Форма | JSON |
| --- | --- |
| \`A | B\` (без аргументов) |
| `A of int` | `{"tag":"A","value":1}`; `[@@dto ~tag:"type" ~content:"data"]` меняет ключи |
| `A of { x : int }` | `{"tag":"A","x":1}` |
| `t option` | `null` / значение |

### Поведение при ошибке тела запроса

Тело не парсится как JSON → `Error.bad_request` (400). JSON есть, но `Json.parse` вернул `Error errors` (не тот тип, отсутствует поле, нарушено правило) → `Error.unprocessable errors` (422), Problem Details:

```json
{ "type": "urn:forge:error:validation", "title": "Unprocessable Entity", "status": 422,
  "detail": "validation failed", "instance": "/cats",
  "errors": [ { "path": ["age"], "rule": "range", "message": "must be between 0 and 40" } ] }
```

Клиентская часть (`Forge_client.Error`) парсит этот формат; `errors` доступны компоненту формы типизированно.

### Связь с jsonkit (решено в фазе 0)

`dto` **не дублирует** jsonkit: весь JSON в Forge — jsonkit. В jsonkit 1.1.0 (opam) уже есть `[@@deriving json]` (`of_json`/`to_json`, бросают `Jsonkit.Of_json_error`) и `[@@deriving jsonschema]` (`t_jsonschema`) — и в native (`Jsonkit.t = Yojson.Basic.t`), и в melange (`Jsonkit.t = Js.Json.t`); `Jsonkit.Jsonschema.t` на обоих — один и тот же полиморфный вариант. Поэтому:

- `Forge_shared.Json.S` повторяет форму jsonkit-дериверов (`of_json` бросает, имя схемы — `t_jsonschema`), и любой тип с `[@@deriving json, jsonschema]` уже является `Json.S`.
- Граница «исключение → result» — одна функция `Json.parse`, она же превращает `Jsonkit.Of_json_error` в `Validation.t` с правилом `type`.
- Собственный вклад `dto` — правила `[@validate]`, `[@exclude]`/`[@expose]`, `~strict`; накопление ошибок с путями — доработка jsonkit, не Forge.
- jsonkit поставляется двумя библиотеками (`jsonkit`, `jsonkit-melange`), поэтому код, который собирается в обоих режимах, — это две dune-библиотеки с одинаковым `name` из одних исходников (`copy_files#`). Так устроен `forge.shared` / `forge-client.shared`; так же `forge new` будет генерировать `shared/` пользовательского проекта.
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

Поддерживаемые типы полей: `int`, `int64`, `float`, `bool` (`true/1/yes`), `string`, `τ option` (отсутствие = `None`, `[@default]` запрещён), `string list` с `[@sep]`, `T.t` через `T.of_string`. Имя переменной без `[@env]` — имя поля в UPPER\_SNAKE. Вложенные записи с `[@prefix "DB_"]` — фаза 2. Файлы `.env` — не ppx, а `Forge.Config.dotenv : string -> unit` в рантайме, вызывается до `load`.

## Данные: Db, sqlgg, \[@@deriving table\], миграции

ORM не пишем. Одна глава Data вместо пяти у Nest: запросы — sqlgg, схема — `table`, миграции — `forge migrate`.

### Forge.Db

```ocaml
module type DRIVER = sig
  type conn
  val connect : string -> conn Lwt.t
  val exec  : conn -> string -> param list -> int Lwt.t          (* affected rows *)
  val query : conn -> string -> param list -> row Lwt_stream.t
  val transaction : conn -> (conn -> 'a Lwt.t) -> 'a Lwt.t
end
module type S = sig
  include DRIVER
  val with_conn : (conn -> 'a Lwt.t) -> 'a Lwt.t   (* из пула *)
end
module Make (D : DRIVER) (Cfg : sig val url : string  val pool : int end) : S
```

Драйверы: `Forge_db_mariadb` (ocaml-mariadb, Lwt) — первый; `Forge_db_pgx` — второй. Оба — отдельные пакеты, чтобы ядро не тянуло C-биндинги. Интерфейс `DRIVER` сделан так, чтобы sqlgg-сгенерированный код работал поверх него через `Sqlgg_traits`.

### sqlgg

Связка `table` + sqlgg — флагманская возможность Forge, которой нет ни у Nest, ни у Rails: **схема — это OCaml-тип, и каждый SQL-запрос проверяется против неё компилятором.** Цепочка:

1. `[@@deriving table]` на записи генерирует `schema : Forge.Table.t` и dune-правило пишет из всех таких типов `schema.sql` (DDL под выбранный диалект).
2. sqlgg получает `schema.sql` + пользовательские запросы (`queries/*.sql` или inline через `ppx_sqlgg`) и генерирует типизированные функции; nullability выводится lattice-анализом из форка и совпадает с `option` в записях.
3. Результаты запросов отображаются в записи через сгенерированный `table`-ом `of_row` (по именам колонок), поэтому `SELECT id, name FROM users` → `User.t`-совместимый тип без ручного маппинга.
4. `forge migrate diff` сравнивает тот же `schema` со снапшотом и готовит черновик миграции.

Эффект: переименовал поле `email` в записи — не компилируются DTO, клиент, loader на фронте, **и все SQL-запросы, где оно упоминается**, а `forge migrate diff` предлагает `ALTER TABLE`. Ни один слой не узнаёт о расхождении в рантайме.

Пример запроса (sqlgg, файл `queries/users.sql`):

```sql
-- @find_adults_by_breed
SELECT u.id, u.email, u.name, u.age
FROM users u JOIN cats c ON c.owner_id = u.id
WHERE c.breed = @breed AND u.age >= @min_age
```

сгенерированная сигнатура (под `Forge.Db` как sqlgg-traits):

```ocaml
val find_adults_by_breed : Db.conn -> breed:string -> min_age:int -> User.t list Lwt.t
```

Использование в сервисе — обычный вызов; контроллер его не видит. Forge здесь добавляет три вещи: `Forge.Db` реализует sqlgg-traits (IO = Lwt, параметры, строки); `table` эмитит `schema.sql` и `of_row`; шаблон `forge new` содержит dune-правила для всей цепочки. Сам sqlgg не форкается дальше и не оборачивается.

### &#91;@@deriving table\]

DDL, снапшот схемы, `of_row` и генерация `schema.sql` для sqlgg — фаза 1 (это вход в цепочку выше). Минимальный CRUD — фаза 2.

```ocaml
type t = {
  id         : int;      [@primary] [@auto]
  email      : string;   [@unique] [@size 255]
  name       : string;
  age        : int option;
  created_at : Ptime.t;  [@default "CURRENT_TIMESTAMP"]
} [@@deriving table ~name:"users", dto]
```

Генерирует `schema : Forge.Table.t` (имя, колонки с SQL-типами, индексы), `create_sql : dialect -> string`, и через `Forge.Table.Crud (Db) (Schema)` — `find : int -> t option Lwt.t`, `insert : t -> int Lwt.t`, `update : t -> unit Lwt.t`, `delete : int -> unit Lwt.t`. Маппинг типов: `int → BIGINT`, `string → VARCHAR(size|TEXT)`, `bool → BOOLEAN`, `float → DOUBLE`, `Ptime.t → TIMESTAMP`, `τ option → NULL`. Связи (`has_many`, `belongs_to`) **не делаем** — это sqlgg.

### Миграции

Фаза 1: `migrations/NNNN_name.sql` + таблица `forge_migrations`; `forge migrate up|down|status`. Фаза 3: `forge migrate diff` сравнивает `schema` всех `table`-типов со снапшотом `migrations/schema.json` и генерирует SQL-черновик, который разработчик правит руками. Автоприменение диффа без просмотра — никогда.

## Генерация клиента и OpenAPI из spec

Контракт живёт в контроллере; `spec` — его рантайм-отражение; всё остальное — кодогенерация из `spec`. Нет отдельного «файла контракта», который мог бы разойтись с кодом.

### Цепочка

1. ppx эмитит в каждый контроллер `spec : Forge.Spec.t`.
2. `Forge.App.run` регистрирует все `spec` в `Forge.Registry` (список, доступный после сборки списка контроллеров).
3. Серверный бинарь принимает флаги `--emit-spec FILE` (JSON всех `spec`) и `--emit-openapi FILE`; с ними он не стартует сервер.
4. `forge client --spec spec.json --out client/gen/` пишет melange-модули; dune rule в шаблоне проекта запускает шаги 3–4 автоматически:

```
(rule (targets spec.json) (deps %{exe:../bin/main.exe})
      (action (run %{exe:../bin/main.exe} --emit-spec spec.json)))
(rule (targets cats_client.ml) (deps spec.json)
      (action (run forge client --spec spec.json --controller cats --out cats_client.ml)))
```

### Генерируемый клиент

На каждый контроллер — модуль `<Prefix>_client`:

```ocaml
(* для каждого route *)
val find_one : id:int -> (Cat.t, Forge_client.Error.t) result Promise.t

(* реализация *)
let find_one ~id =
  Forge_client.Http.request `GET
    ~path:(Forge_client.Path.build "/cats/:id" [ ("id", Forge_client.Codec.int.to_string id) ])
    ~query:[]
    ~decode:Cat.of_json
```

Правила отображения: path/query-параметры → labelled/optional с теми же именами и типами (`Codec` по имени из `spec`); `body` → `~body:T.t` с `T.to_json`; guard-параметры отсутствуют; `returns` → `Unit | Text | Json T | Raw` → `unit | string | T.t | Forge_client.Http.response`; `sse` → `T.t Forge_client.Sse.t` (обёртка над `EventSource`). Типы `T` резолвятся по имени модуля из `spec` — поэтому DTO обязаны лежать в `shared/`; генератор не проверяет это, проверит компилятор.

### Forge\_client.Http

```ocaml
val base_url : string ref                        (* "" = same origin *)
val request : [ `GET | `POST | … ] -> path:string -> ?query:(string * string list) list ->
  ?body:Jsonkit.t -> decode:(Jsonkit.t -> ('a, string) result) -> ('a, Error.t) result Promise.t
val interceptors : (request -> request) list ref  (* auth header, csrf token *)
```

`Forge_client.Error.t` — тот же envelope, что `Forge.Error.t`, плюс `Network of string` и `Decode of string`.

### OpenAPI

`--emit-openapi` строит документ 3.1: `paths` из `spec.routes`, `components.schemas` из `jsonschema` всех встреченных DTO (имя модуля = имя схемы), `parameters` из `Codec.schema`, `responses` с кодом из `status` и envelope ошибки для 4xx. Теги — префиксы контроллеров. Описания — из docstrings `(** … *)` над хендлером, если ppx их сохранил в `spec` (фаза 2). Swagger UI — `Forge.Openapi.ui : path:string -> Dream.route` поверх статического `swagger-ui-dist`.

## Frontend: Forge\_client и typed router

Модель — TanStack Router: маршрут как значение с типами `params`/`search`/`data`, `Link` и `navigate` проверяются компилятором, loader на маршруте, вложенные layouts. React — через reason-react, разметка — `.mlx`.

### Forge\_client.Router

```ocaml
type ('params, 'search, 'data) route

val root  : ?layout:(children:React.element -> React.element) -> unit -> (unit, unit, unit) route

val child :
  (_, _, _) route ->                               (* родитель: его путь — префикс, его layout — обёртка *)
  path:'params Path.t ->
  ?search:'search Search.t ->                      (* по умолчанию unit *)
  ?loader:('params -> 'search -> 'data Promise.t) -> (* по умолчанию unit *)
  ?pending:React.element ->
  ?on_error:(Error.t -> React.element) ->
  component:(data:'data -> params:'params -> search:'search -> React.element) ->
  ('params, 'search, 'data) route

val make : any_route list -> t                      (* any_route = Any : (_,_,_) route -> any_route *)
val provider : t -> React.element                  (* <Router.provider router /> *)

val link : ('p, 's, _) route -> params:'p -> search:'s -> ?replace:bool -> children:React.element -> React.element
val navigate : ('p, 's, _) route -> params:'p -> search:'s -> unit
val href : ('p, 's, _) route -> params:'p -> search:'s -> string
val use_params : ('p, _, _) route -> 'p
val use_search : (_, 's, _) route -> 's
val use_loader_data : (_, _, 'd) route -> 'd
val use_navigate : unit -> (unit -> unit)          (* назад/вперёд *)
val preload : (_, _, _) route -> params:_ -> search:_ -> unit   (* prefetch на hover *)
```

Матчинг — по `Path.t` (см. ниже) сверху вниз по дереву; `search` парсится `Search.t`; при ошибке парсинга — `on_error` ближайшего предка. Loader вызывается при входе и при изменении `params`/`search`; результат кэшируется по сериализованному ключу (как TanStack `loaderDeps`).

### Path, Search, Params — три ppx в forge-client

`Path.t` — это `Routes.path` из той же библиотеки routes, что и на сервере: матчинг через `Routes.match'`, `href` через `Routes.sprintf`. `[%path "/cats/:id"]` — сахар: ppx строит `Routes.(s "cats" / int /? nil)` и, если в области видимости есть `type params = {…} [@@deriving params]`, генерирует пару `fun id -> { id }` / `fun { id } -> id`, чтобы роут работал с записью, а не с curried-аргументами. Без `params`-типа сегменты `:name` — `string`. Имена в `[%path]` и поля записи сверяются ppx; типы — компилятором. Сгенерированный API-клиент использует те же `Routes.path` из `spec` (`Routes.sprintf`), так что путь к API и путь страницы печатаются одним механизмом.

```ocaml
type params = { id : int } [@@deriving params]      (* → params_codec : params Path.codec *)
type search = { page : int [@default 1]; q : string option } [@@deriving search]
(* → search_codec : search Search.t: парсинг/печать query string, дефолты, option *)
```

Поддерживаемые типы — те же, что в серверном `Codec`: `int`, `float`, `bool`, `string`, `T.t` с `T.codec`, `option`, `list`. Это одно и то же множество намеренно: сгенерированный API-клиент и роутер страниц используют одни кодеки.

### Компоненты

`Link` — обычный компонент reason-react над `Router.link`; `.mlx`-синтаксис даёт `<Link route=… params=… search=…>`. Ошибка в `params` — ошибка типов в компоненте, не в рантайме.

### Что не делаем

File-based routing (`routes/cats.$id.tsx`) — не нужен: дерево из значений даёт то же самое без кодогенерации по файловой системе. SSR Melange-компонентов — не в скоупе; серверный HTML — Dream eml/tyxml как опция.

## Тестирование

Четыре уровня, каждый — свой каталог в `test/`. Nest-овский `Test.createTestingModule` не нужен: подмена зависимости — применение функтора/`register` к другому модулю.

| Уровень | Инструмент | Что проверяет |
| --- | --- | --- |
| ppx | ppx\_expect на `-dsource` выводе | каждая трансформация: эталонный сгенерированный код; каждая ошибка ppx — отдельный тест с ожидаемым сообщением |
| core | alcotest | `Error.to_response`, `Codec`, `Validation`, `Refined`, `Spec.to_json`, OpenAPI-генератор, `Route.handle` с подменённым запросом |
| контроллеры (unit) | alcotest + `Dream.test` | `Cats_controller.register (module Fake_cats)` → `Forge.App.handler` → `Dream.test handler (Dream.request ~method_:`GET \~target:"/cats/1" "")\` → статус/тело |
| e2e | alcotest, запуск `examples/cats` | сервер на случайном порту; сгенерированный native-вариант клиента (тот же генератор с `--target native` поверх cohttp) ходит по всем маршрутам; OpenAPI валидируется схемой 3.1 |

Пример unit-теста контроллера с фейковым сервисом:

```ocaml
module Fake_cats : Cats_service.S = struct
  let add _ = Lwt.return { Cat.id = 1; name = "x"; age = 1; breed = "siamese" }
  let find_all () = Lwt.return []
  let find = function 1 -> Lwt.return_some { Cat.id = 1; … } | _ -> Lwt.return_none
end

let app = Forge.App.handler [ Cats_controller.register (module Fake_cats) ]

let test_404 () =
  let%lwt resp = Dream.test app (Dream.request ~method_:`GET ~target:"/cats/2" "") in
  Alcotest.(check int) "status" 404 (Dream.status resp |> Dream.status_to_int);
  Lwt.return_unit
```

Клиентский роутер тестируется в node через melange: `Path` матчинг и `Search` round-trip — property-тесты (`Search.parse (Search.print s) = Ok s`). Если принят typegist, генераторы для property-тестов берутся из gist.

## CLI forge

Бинарь на cmdliner, зеркало `nest` CLI. Генераторы пишут файлы по шаблонам из `examples/cats`; ничего не делают «магически» — только файлы, которые разработчик и так написал бы руками.

| Команда | Делает | Nest |
| --- | --- | --- |
| `forge new NAME` | dune-project, 4 каталога, cats-пример, CI, `.ocamlformat`, opam-файлы | `nest new` |
| `forge generate controller cats` | `server/cats_controller.ml` с `[@@@controller]` и CRUD-заготовкой, `shared/cat.ml`, `shared/create_cat_dto.ml` | `nest g resource` |
| `forge generate service cats` | `server/cats_service.ml` + `.mli` с `module type S` | `nest g service` |
| `forge generate dto name` | `shared/name_dto.ml` | — |
| `forge client --spec --out [--target melange\|native]` | типизированные клиенты из spec | openapi-generator |
| `forge openapi --spec --out` | OpenAPI 3.1 JSON; то же, что `main.exe --emit-openapi` | `@nestjs/swagger` |
| `forge migrate up\|down\|status\|new NAME` | SQL-миграции (фаза 1), `diff` (фаза 3) | TypeORM CLI |
| `forge routes` | таблица маршрутов из spec | — |
| `forge start [--watch]` | `dune build -w` + перезапуск `main.exe`; melange-пересборка — через dune же | `nest start --watch` |

`forge routes` и `forge openapi` — обёртки над флагами серверного бинаря, чтобы не дублировать `spec`-сериализацию. Шаблоны — файлы в `src/cli/templates/`, не строки в коде.

## Заимствования из Spring

Nest задаёт структуру; из Spring берём пять вещей, которых у Nest нет или они слабее. Все пять в Spring реализованы runtime-прокси (AOP); у нас это compile-time переписывание ppx, поэтому ловушек вроде self-invocation нет.

| Spring | Forge | Фаза |
| --- | --- | --- |
| Problem Details (RFC 9457, `application/problem+json`) | формат `Error.to_json` и клиентского `Error.t` | 0 |
| `@PreAuthorize("… #id == principal.id")` | `[@@authorize f]` — типизированная функция над извлечёнными параметрами | 2 |
| `@Transactional` | `[@@transactional]` + `[@from Db.tx]` | 2 |
| Actuator | `Forge.Actuator.routes` | 2 |
| Profiles | `FORGE_ENV` + слои `config/*.env` | 1 |

### Problem Details — заменяет envelope ошибки

Этот формат **заменяет** JSON ошибки, описанный в разделах Core и dto. `Error.t` остаётся тем же, меняется сериализация:

```json
{ "type": "urn:forge:error:validation", "title": "Unprocessable Entity", "status": 422,
  "detail": "validation failed", "instance": "/cats",
  "errors": [ { "path": ["age"], "rule": "range", "message": "must be between 0 and 40" } ] }
```

`type` = `urn:forge:error:<code>` (переопределяется `Error.make ~type_`), `instance` = `Dream.target`, `details` раскладываются как расширения верхнего уровня. Content-Type `application/problem+json`. `Forge_client.Error` парсит ровно это.

### `[@@authorize]`

Замыкание вызывается после извлечения всех параметров (path, query, body, `[@from]`) и до тела. Лейблы — подмножество лейблов хендлера; лишний или с неверным типом — ошибка компиляции. Возврат — `bool Lwt.t` (false → 403) или `(unit, Error.t) result Lwt.t`.

```ocaml
let update (module Cats : Cats_service.S)
    ~(user : User.t [@guard Auth.current]) ~(id : int) ~(body : Update_cat_dto.t) : Cat.t Lwt.t = …
[@@put ":id"]
[@@authorize fun ~user ~id -> let%lwt owner = Cats.owner_of id in Lwt.return (Auth.is_admin user || owner = user.id)]
```

Отличие от `[@@guards]`: guard видит только запрос, `authorize` — типизированные параметры. Это закрывает SpEL-кейсы без строк.

### `[@@transactional]`

```ocaml
let transfer (module Db : Db.S) ~(conn : Db.conn [@from Db.tx]) ~(body : Transfer_dto.t) : unit Lwt.t = …
[@@post] [@@transactional]
```

Семантика: обёртка открывает `Db.transaction`, кладёт `conn` в `Dream.field` `Db.tx_field`, выполняет тело; `Ok` → commit, `Error`/исключение → rollback и обычный маппинг ошибки. `[@from Db.tx]` читает это поле; `[@from Db.tx]` без `[@@transactional]` — ошибка ppx (проверяется синтаксически по имени). Опции: ``[@@transactional ~isolation:`Serializable]``, `~read_only:true`. Вложенные транзакции не поддерживаются: второй `[@@transactional]` в цепочке вызовов — ошибка при старте (детектируется по `spec`), не молчаливый savepoint.

### Actuator

`Forge.Actuator.routes : config:(module Config.S) -> ?metrics:bool -> unit -> Forge.Controller.t`, монтируется как обычный контроллер под `/actuator`:

| Путь | Содержимое |
| --- | --- |
| `/health` | `{"status":"up","checks":{"db":"up"}}`; проверки регистрируются `Actuator.check ~name f` |
| `/info` | версия, git sha, время сборки (из dune `%{version}` и `git describe` в сборке) |
| `/env` | конфиг через `Config.pp` — `[@secret]` замазаны |
| `/routes` | все `spec` в JSON — то же, что `forge routes` |
| `/metrics` | Prometheus text format: latency по маршруту, коды, `Gc.quick_stat` |
| `/openapi.json` | то же, что `--emit-openapi` |

Закрывается `[@@@guards]` как любой контроллер; по умолчанию — только с loopback.

### Profiles

`Forge.Config.dotenv` читает `config/default.env`, затем `config/${FORGE_ENV}.env`, затем реальное окружение; позже — приоритетнее. Условные провайдеры в `main.ml` — обычный `match config.env with`; атрибут `[@profile]` не нужен.

## Заимствования из IHP

IHP (Rails для Haskell) силён там, где Nest и Spring пусты: живые данные без ручных подписок, веб-инструменты разработчика и DB-backed jobs. Берём четыре идеи; одна из них у нас получается строже, чем в IHP.

| IHP | Forge | Фаза |
| --- | --- | --- |
| Auto Refresh (страница обновляется при изменении таблиц, которые она читала) | Live loaders: зависимости маршрута от таблиц известны **статически** из sqlgg | 2 |
| Scripts (одноразовые скрипты с контекстом приложения) | `forge generate script` + `forge run NAME` | 1 |
| Jobs как таблицы (`CREATE TABLE … job`) | `[@@deriving table ~job]` + воркер | 3 |
| IDE: Schema Designer, Data browser, Logs | `forge dev` — веб-UI поверх Actuator | 3 |
| Schema.sql как источник правды, типы из него | **не берём** направление, берём импорт: `forge import-schema` для brownfield | 1 |

### Live loaders — Auto Refresh через статический анализ

IHP отслеживает таблицы, прочитанные при рендере, в рантайме, и слушает Postgres `LISTEN/NOTIFY`. У нас обе половины известны на этапе компиляции, потому что sqlgg парсит SQL:

1. sqlgg знает, какие таблицы **читает** каждый запрос и какие **пишет** (`INSERT/UPDATE/DELETE`). Forge расширяет сгенерированный код метаданными `reads : string list`, `writes : string list` на функцию.
2. Хендлер, вызывающий сервисные функции, не знает их таблиц статически (это уже за пределами ppx). Поэтому зависимости объявляются на хендлере: `[@@live ["cats"; "users"]]`, а e2e-тест проверяет, что объявленное ⊇ фактически прочитанного (рантайм считает `reads` вызванных sqlgg-функций в режиме `FORGE_ENV=test`). Расхождение — падение теста, не тихая потеря обновлений.
3. После коммита транзакции (или после любой пишущей sqlgg-функции вне транзакции) `Forge.Live.publish` рассылает `Table_changed t` — без триггеров в БД, поэтому работает и на MariaDB/TiDB, где нет `NOTIFY`. Для Postgres опционально `LISTEN/NOTIFY`, чтобы ловить внешние записи.
4. `spec.route.live : string list` попадает в сгенерированный клиент: `Cats_client.find_all` получает `~subscribe:true`, а `Router.child ~live:true` перезапускает loader при событии по SSE-каналу `/__forge/live`. Для multi-process — pub/sub через Redis или Postgres; один процесс — in-memory.

Результат: `Cats.index` на фронте обновляется, когда кто-то добавил кота, без единой строки кода подписки в приложении — и с проверяемым списком зависимостей.

### Scripts

`forge generate script backfill_ages` создаёт `scripts/backfill_ages.ml` с заготовкой `let main (module Db : Db.S) (config : Config.t) = …`; `forge run backfill_ages` собирает и запускает с тем же `Config.load` и пулом, что и сервер. Это замена `rake`-задачам и «вот бы быстро прогнать одну миграцию данных».

### Jobs как таблицы

```ocaml
type t = { id : int [@primary] [@auto]; cat_id : int; email : string }
[@@deriving table ~name:"send_welcome_jobs" ~job]
```

`~job` добавляет колонки `status`, `attempts`, `run_at`, `last_error`, `locked_by` и генерирует `enqueue : t -> unit Lwt.t` и `Worker.run ~handler:(t -> (unit, string) result Lwt.t) ~concurrency ~retry`. Очередь — сама таблица с `SELECT … FOR UPDATE SKIP LOCKED`; никакого Redis для базового случая. Это реализация главы Queues (фаза 3) по умолчанию; BullMQ-подобный бекенд — только если понадобится.

### forge dev

Веб-UI на том же порту под `/__forge/`: список маршрутов (`spec`), схема и данные таблиц (из `Forge.Table.Registry` + sqlgg-запросов, редактирование строк), логи запросов в реальном времени (SSE), статус live-подписок, OpenAPI. Schema Designer как в IHP не делаем: схема — OCaml-код, редактор ей не нужен. Включается только при `FORGE_ENV=dev`.

### Направление истины: тип, не SQL

IHP держит `Schema.sql` и генерирует типы. Мы держим OCaml-записи (там живут opaque-типы и `dto`) и генерируем `schema.sql`. Для brownfield (существующая MariaDB/TiDB) — `forge import-schema --url … --out shared/gen/`: sqlgg парсит `SHOW CREATE TABLE` и пишет записи с `[@@deriving table, dto]`, которые дальше правятся руками и становятся источником. Одноразовый импорт, не двусторонняя синхронизация.

## Фазы и критерии приёмки

Фаза закрыта, когда её критерий выполнен в CI. Порядок внутри фазы — сверху вниз; каждая строка — отдельная задача для Claude Code с собственным PR.

### Фаза 0 — фундамент и решения (1 неделя) — выполнена

| Задача | Критерий |
| --- | --- |
| Репозиторий, dune-project, 4 opam-пакета, CI (build + test на 5.5) | `dune build @all` зелёный на пустых пакетах |
| Проверить Melange под 5.5; зафиксировать правило версий для `shared/` | решение записано в разделе «Стек» |
| Оценить typegist (бенчмарк кодека, Melange-сборка, opam-статус) | решение (а)/(б) записано в разделе dto |
| Осмотреть jsonkit: что есть из `of_json/to_json`; решить, где живут кодеки | решение записано в разделе dto |
| `Forge.Error`, `Response`, `Codec`, `Validation`, `Refined`, `Spec`, `Controller`, `run`/`app` по `.mli` из раздела Core | alcotest на каждый модуль; `Forge.App.handler []` отвечает 404 через `Error.to_response` |

### Фаза 1 — ядро, cats end-to-end (3–4 недели)

| Задача | Критерий |
| --- | --- |
| ppx `controller`: атрибуты, классификация, `Make`/`register`/`spec`, все ошибки | ppx\_expect на каждый пункт раздела ppx; cats-контроллер компилируется |
| ppx `dto` (базовый, `~strict`, `[@validate]`, opaque-поля через `Json.S`) | round-trip тесты; 422-envelope совпадает с описанным |
| `Forge_shared.Refined` (String, Int, Enum, Regex, Email, Make) | схемы содержат ограничения; `codec` работает в path/query |
| ppx `config` | `load` собирает все ошибки сразу |
| `--emit-spec`, `--emit-openapi`; `forge client` (melange + native) | OpenAPI проходит валидацию 3.1; native-клиент проходит e2e по cats |
| `Forge_client`: `Http`, `Error`, `Promise` | e2e из браузера (melange-тест в node) |
| `Forge_client.Router` + `[%path]`, `search`, `params` | тесты матчинга и round-trip; `Link` с неверными params не компилируется (expect-тест на ошибку типов) |
| `Forge.Db` как sqlgg-traits + `Forge_db_mariadb`; `table`: `schema`, `schema.sql`, `of_row` | sqlgg-запрос против `schema.sql` компилируется и выполняется в e2e |
| `forge migrate up/down/status/new` | e2e применяет миграции на пустую БД |
| `forge new`, `forge generate controller/service/dto` | сгенерированный проект собирается и проходит свой e2e |
| Docs: главы Overview + Fundamentals + Validation/Serialization/Configuration + Data | каждая глава содержит порт Nest-примера, который компилируется в `docs/` как mdx-тест |

**Критерий фазы 1:** `examples/cats` — порт Nest-примера — собирается (`dune build @all`), `dune test` зелёный, `forge client` регенерирует клиент без диффа, страница `/cats/1` в браузере показывает кота из БД.

### Фаза 2 — реальное приложение (4–6 недель)

`[@@sse]` и `[@@@gateway]`/`[@@subscribe]` для websockets с типами из shared; `[@@cron]`; `Events` (типизированная шина); `[@@cache]`; `table` CRUD; `dto` mapped types (`~partial_of`, `~pick_of`); auth-стратегии (session, JWT) + `Auth.role`; helmet/CORS/rate-limit middleware; `[@@@version]`; docstrings → OpenAPI; `Forge_db_pgx`. Критерий: главы Security, HTTP, WebSockets, Events, Task scheduling, Caching закрыты.

### Фаза 3 — экосистема

`forge migrate diff`; queues; GraphQL code-first; resilience/idempotency/outbox; i18n; file storage; microservice-транспорты. Приоритизируется по первому реальному проекту на Forge.

### Карта глав docs.nestjs.com

| Раздел Nest | Статус в Forge |
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
| Recipes | REPL = utop, Hot reload = dune -w, Serve static = Dream.static, Commander = cmdliner, CRUD generator = `forge generate`; CQRS — 3 |

## Конвенции для разработки и открытые вопросы

Эти правила — для `CLAUDE.md` репозитория; они перекрывают любые умолчания.

### Код

- OCaml 5.5, `(lang dune 3.23)`, ocamlformat 0.29 с профилем `default`; CI падает на неотформатированном коде.
- Минимум кода, никаких функций ради одного вызова. Illegal states unrepresentable: `option`/`result`/варианты вместо флагов и проверок. Никаких `assert false`, `failwith` в библиотечном коде, `Obj.magic`.
- Каждый публичный модуль имеет `.mli`; `Forge.*` — ровно сигнатуры из раздела Core; изменение сигнатуры — правка этого документа в том же PR.
- Сгенерированный ppx-код содержит только вызовы `Forge.Route`/`Forge_shared.Json`/`Forge_shared.Scalar`, без логики; логика — в рантайме, где её можно тестировать без ppx.
- Modular explicits — только в `server/` и `bin/`; `shared/` и `client/` — синтаксис, который собирает Melange.
- Dream не оборачивается: `Dream.request`, `Dream.middleware`, `Dream.response` в публичных сигнатурах Forge допустимы и желательны.

### ppx

- Один драйвер `forge.ppx` (`ppxlib` ≥ 0.38); трансформации регистрируются по одной, каждая — свой файл и свой набор expect-тестов.
- Все ошибки — `Location.raise_errorf` с локацией на виновный узел и текстом вида «что не так → что сделать»: ` handler find_one: missing return type annotation; add  `: Cat.t Lwt.t\`».
- Никаких предупреждений вместо ошибок; никакой «догадки» по умолчанию, если аннотация отсутствует.
- Сгенерированные имена с префиксом `__forge_`; пользовательские имена не затеняются.

### Тесты и docs

- Для каждой трансформации: expect-тест эталонного вывода + по тесту на каждую ошибку.
- `examples/cats` — всегда зелёный; это интеграционный тест ядра.
- Главы в `docs/` повторяют оглавление Nest; каждая содержит порт Nest-примера, который компилируется (mdx-тест). Глава без компилируемого примера не считается написанной.

### Процесс для Claude Code

- Одна строка таблицы фазы = один PR с тестами. Начинать с фазы 0 по порядку; фазу 1 — с ppx `controller`.
- Перед реализацией раздела перечитать его в этом документе; если дизайн не сходится с реальностью (версия библиотеки, невозможность в ppx), сначала правка документа с обоснованием, потом код.
- Не расширять скоуп фазы: идея, не вошедшая в таблицу, записывается в «Открытые вопросы».

### Открытые вопросы

- [x] Melange под OCaml 5.5: есть `melange.7.0.1-55`; один switch, синтаксис 5.5 разрешён везде (фаза 0).
- [x] typegist: вариант (б), не используется (фаза 0, раздел dto).
- [x] jsonkit: `of_json`/`to_json`/`t_jsonschema` есть на обоих бэкендах; `Json.S` повторяет их форму (фаза 0, раздел dto).
- [ ] jsonkit: режим декодирования с накоплением ошибок и путями (`["age"]`) — нужен для аппликативных 422; до него — первая ошибка без пути.
- [ ] Регулярные выражения в `Forge_shared` (`Validation.regex`, `Refined.Regex`): `Str` есть только в native; варианты — `re` (проверить сборку в melange) или своя реализация на `Js.Re` за общим интерфейсом.
- [ ] Длина строк в `Validation.min_length`/`max_length`: `String.length` считает байты в native и UTF-16-единицы в JS; для не-ASCII нужен подсчёт code points, одинаковый на обоих концах.
- [ ] sqlgg: точная форма traits-интерфейса форка для `Forge.Db` (IO = Lwt) и способ отдать `schema.sql` в dune-правило без ручного перечисления типов (вариант: `table` регистрирует схему в `Forge.Table.Registry`, бинарь `--emit-schema`).
- [ ] Имя: `Forge` — рабочее; проверить коллизии в opam перед публикацией.
- [ ] `.mlx` против reason-синтаксиса для JSX: `.mlx` по умолчанию, пока не упрёмся в ограничения.
- [x] Dream: вышел `1.0.0`, зависимость `dream >= 1.0.0`.

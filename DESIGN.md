# Kre — design of a full-stack web framework in OCaml

Oct 31, 2026 · @Mr

## Goals and principles

Kre is a full-stack framework in OCaml 5.5: the server on Dream, the frontend on Melange, shared code in `shared/`. The Kre documentation is split into chapters (see "Map of docs chapters"); a chapter is closed when its examples are written in Kre and compile.

Principles that settle disputed questions during development:

1. **Do not reproduce what OCaml already has; DI happens at build time, not at runtime.** Dependencies are wired by the ppx `[%wire]`, which finds providers among modules and functors and injects them into their consumers: DI errors are compile errors. There is no runtime container, no tokens, no reflection; OOP is not used — only modules, functors and functions. A module system makes a separate module registry, a DI container, forward references and runtime discovery unnecessary. In Kre a module = a singleton provider, `.mli` = exports, `main.ml` = composition root, dependencies = module-dependent functions (modular explicits, OCaml 5.5). Dependencies are resolved at compile time, not at startup.
2. **ppx only where reflection is needed.** Routes from handler signatures, DTO codecs and validation, config from env, typed paths on the frontend. Everything else is plain functions and modules.
3. **Dream is not wrapped.** `Dream.request`, `Dream.middleware`, `Dream.response`, sessions, CSRF, websockets, static — are used directly. Kre adds a layer above; it does not hide the layer below.
4. **The controller is the source of truth.** The typed Melange client and OpenAPI are generated from it (via `spec`). The contract is never duplicated by hand.
5. **One syntax for server and client.** User code reads the same on both ends: attributes on `let`, `[@@deriving …]` on types.
6. **Illegal states unrepresentable, minimal code.** No `assert false`, no `Obj.magic`; ppx errors go through `Location.raise_errorf` with a message that explains what to fix.

Not done in the first phases: ORM (sqlgg + `table` instead), GraphQL, microservices/transporters, queues, MongoDB, platform-agnosticism (Dream only), a dependency graph UI, Observability SaaS.

## Stack and versions

Server and client use OCaml 5.5.1 in one opam switch: Melange `7.0.1-55` is built for 5.5, and modular explicits compile both to native and to JS (verified in phase 0).

| Component | Version / choice | Why |
| --- | --- | --- |
| OCaml | 5.5.0 ([released June 19, 2026](https://ocaml.org/changelog/2026-06-19-ocaml-550)) | modular explicits `(module M : S) -> …`, polymorphic parameters, GC |
| ppxlib | ≥ 0.38.0 (0.39.0 in the switch) | all Kre ppx |
| dune | ≥ 3.21 (3.24 in the switch) | `(modes :standard melange)` for shared, `melange.emit` |
| Dream | 1.0.0 | HTTP, sessions, CSRF, websocket, static |
| routes | 2.0.0 | typed paths on both ends |
| Lwt + lwt\_ppx | 6.1 | server monad; `let%lwt`, `match%lwt` |
| Melange | 7.0.1-55 (OCaml 5.5) | frontend, `Js.Promise` |
| reason-react + mlx | current | components, JSX syntax in `.mlx` |
| jsonkit | in-house | JSON type and `[@@deriving jsonschema]`, native + melange |
| sqlgg / ppx\_sqlgg | in-house fork | typed SQL |
| cmdliner | current | `kre` CLI |
| ocamlformat | 0.29 (5.5 syntax) | formatting |
| cram (dune) + alcotest | current | tests: ppx — cram on `pp.exe` output, the rest — alcotest |

**Two base library decisions.** All JSON is [jsonkit](https://github.com/melange-community/jsonkit): the `Jsonkit.t` type, codecs, `[@@deriving jsonschema]`; Kre does not define its own JSON type and does not generate codecs itself — whatever is missing is added to jsonkit. All paths are [routes](https://github.com/anuragsoni/routes) (anuragsoni): a typed bidirectional router, pure OCaml, works in Melange too; one `Routes.path` value gives matching on the server, `sprintf` for clients and `string_of_path` for OpenAPI. `Dream.router` with string patterns is not used; `Kre.App.handler` matches via `Routes.one_of`/`Routes.match'` and stays a plain `Dream.handler`.

**Compiler version rule (decided in phase 0).** Melange 7.0.1-55 supports OCaml 5.5, so the client needs no separate switch, and 5.5 syntax (modular explicits) is allowed everywhere, including `shared/` and `client/`. `dune-project` requires `ocaml >= 5.5 & < 5.6`; the project's local switch is `opam switch create . 5.5.1`.

**Monads.** Server: `Lwt.t`; client: `Js.Promise.t`. `Kre_client.Promise` provides `return`, `let*`, `let+` over `Js.Promise.t` in Melange and over `Lwt.t` in native, so code on top of the client builds in both modes (there is no `Promise.t` type alias). No type in `shared/` mentions a monad: the contract between the ends is only data (DTOs) and `spec`.

**Lwt conventions.** User code uses `lwt_ppx` (`let%lwt`, `match%lwt`, `try%lwt`); generated ppx code uses `Lwt_result.Syntax` (`let*` over `('a, Error.t) result Lwt.t`), without `lwt_ppx`, so that `kre.ppx` does not depend on the order in which preprocessors are applied. Exceptions in handlers are caught in `Kre.Route.handle` via `Lwt.catch`, not via `try%lwt` in generated code. Lifecycle: `Lwt_switch` (`run ~on_shutdown` attaches to it). Per-handler timeout: `[@@timeout 5.0]` → `Lwt.pick` with `Lwt_unix.sleep`, off by default. Eio and `Lwt_eio` are not used; a move to effects happens only together with replacing Dream, through the same `Kre.Route.handle`.

**Multicore.** Dream is single-domain. Horizontal scaling is N processes behind a load balancer; `Kre.App.run ~domains` is not planned.

## Repository layout and packages

One monorepo `kre`, four opam packages. The example `examples/cats` is the running example of the docs and also an integration test.

```
kre/
  dune-project
  kre.opam          # kre.shared (Kre_shared, native + melange) and kre (Kre, server runtime, native)
  kre-ppx.opam      # ppx: controller, dto, config, table
  kre-client.opam   # Kre_client: Http, Router, Path, Search + ppx search/params/path (melange)
  kre-cli.opam      # kre binary
  src/
    shared/           # Kre_shared: Validation, Codec, Json, Refined — builds in both modes
    core/             # Kre: Error, Response, Guard, Spec, Route, Controller, App
    ppx/              # one driver, several transformations (see the ppx section)
    client/           # melange library
    cli/              # cmdliner
  examples/cats/
    dune-project
    shared/           # Cat, Create_cat_dto  (modes :standard melange)
    server/           # Cats_service, Cats_controller, Config, Db
    client/           # Routes, Cats_page.mlx, gen/cats_client.ml (generated)
    bin/main.ml
  test/
    ppx/              # cram tests on driver output: a reference for each transformation + each error
    core/             # alcotest: Error.handler, Codec, Validation, Spec→OpenAPI
    e2e/              # starts examples/cats, calls Dream.test and the generated client
  docs/               # the Kre documentation, one file per chapter
```

Dependency rules between packages:

- `kre.shared` depends only on jsonkit (native) / jsonkit-melange (melange) and `kre.text` / `kre-client.text` (string operations that differ per backend); it does not see Dream or Lwt.
- `kre` depends on `kre.shared`, Dream, Lwt, routes, jsonkit; it does not depend on ppx.
- `kre-ppx` depends on ppxlib and jsonkit (for `dto`); generated code refers only to `Kre.*`, `Kre_shared.*` and `Jsonkit.*`.
- `kre-client` depends on melange, reason-react, jsonkit-melange, `kre.shared`; it does not depend on `kre`.
- The user project's `shared/` depends only on jsonkit and `kre.shared` (+ `kre-ppx` for `dto`) and builds in both modes.

Module names: `Kre_shared` (shared by both ends: `Kre_shared.Refined`, `Kre_shared.Codec`, …), `Kre` (server: `Kre.Error`, `Kre.App`, …), `Kre_client`, `Kre_ppx` (not exported to the user). The split is a phase 0 decision: `shared/` builds in Melange and cannot depend on the server library, which pulls in Dream. `Kre_shared` is not re-exported from `Kre` (the "no aliases" rule).

## Running example: cats

This code is the phase 1 acceptance criterion: it must compile and work end-to-end. It covers a controller, a service and a DTO: `Cats_controller`, `Cats_service`, `Create_cat_dto`.

**shared/cat.ml** — the response type, visible to both ends:

```ocaml
type t = { id : int; name : string; age : int; breed : string }
[@@deriving dto]
(* generates: of_json, to_json, jsonschema *)
```

**shared/create\_cat\_dto.ml** — the request body. Constraints live in the opaque field types, not in attributes: an invalid `Name.t` value does not exist.

```ocaml
module Name  = Kre_shared.Refined.String (struct let name = "name"  let min = 1 let max = 64 end)
module Age   = Kre_shared.Refined.Int    (struct let name = "age"   let min = 0 let max = 40 end)
module Breed = Kre_shared.Refined.Enum   (struct let name = "breed" let values = [ "siamese"; "persian"; "maine coon" ] end)

type t = { name : Name.t; age : Age.t; breed : Breed.t }
[@@deriving dto]
(* generates: of_json, to_json, jsonschema, validate (identity here) *)

(* escape hatch for a one-off rule without its own type: *)
type quick = { nickname : string [@validate max_length 16] } [@@deriving dto]
```

**server/cats\_service.ml** — a provider. Module = singleton, the state lives inside (`private readonly cats: Cat[] = []`):

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

**server/cats\_controller.ml** — a controller. Handler module parameters = dependencies (modular explicits):

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

**server/logger\_middleware.ml** — middleware is just a `Dream.middleware`:

```ocaml
let use : Dream.middleware = fun next req ->
  Dream.log "Request...";
  next req
```

**bin/main.ml** — the composition root; this is the `AppModule`:

```ocaml
let () =
  let config = Config.load_exn () in
  Kre.App.run ~port:config.port
    ~middleware:[ Dream.logger ]
    [ Cats_controller.register (module Cats_service) ]
```

**client/gen/cats\_client.ml** — generated by the `kre client` command from the server's `spec`:

```ocaml
val find_all : ?limit:int -> unit -> (Cat.t list, Kre_client.Error.t) result Promise.t
val find_one : id:int -> (Cat.t, Kre_client.Error.t) result Promise.t
val create   : body:Create_cat_dto.t -> (Cat.t, Kre_client.Error.t) result Promise.t
(* the user parameter with [@guard] does not reach the client *)
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

**client/cats\_page.mlx** — a component; a `Link` with wrong `params` does not compile:

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

## A whole application: shelter

A cat shelter: users, cats, adoptions. It uses everything in this document: opaque types, `table` + sqlgg, modular explicits, guards, `[@@authorize]`, `[@@transactional]`, live loaders, routes, the typed router on the frontend, Actuator. This is the second integration example (`examples/shelter`), an acceptance criterion of phase 2.

```
shelter/
  shared/   user.ml  cat.ml  adoption.ml  login_dto.ml  session.ml
            create_cat_dto.ml  rename_dto.ml  adopt_dto.ml      (+ melange/ — the same files)
  schema/   credential.ml  schema.ml                            (server-only table; prints DDL/CRUD)
  server/   config.ml  settings.ml  database.ml  inserted.ml  auth.ml
            users_service.ml  cats_service.ml  adoptions_service.ml
            auth_controller.ml  cats_controller.ml  adoptions_controller.ml
            sql/queries.sql  migrations/0001_init.sql
  client/   pages.mlx  routes.mlx  scenario.mlx                 (*_client.ml is generated by kre client)
  bin/      main.ml                                             (let app = [%wire])
  test/     test_shelter.ml  run_scenario.ml
```

**As built (phase 2)** — differences from the sketch below, each with its reason:

- Login uses JWT (`Kre.Jwt`), not a cookie session: `fetch` in node does not store cookies, and the e2e test runs from node. The token carries `User.t` in its claims, so `Auth.current` is a `Guard.check` with no database query and no middleware; `Auth.admin` gives the evidence `Auth.Admin.t`.
- Passwords live in a separate `credentials` table (`schema/credential.ml`, PBKDF2-SHA256 from `kdf`, comparison with `Eqaf`), not in a `password_hash` field of `User.t`: the type sent to the client has no hash at all. `Credential.verify` returns `User.Id.t` as evidence.
- `role` and `status` are variants with `[@@deriving dto]` that became scalars (see "Variants" in dto); there are no `Ptime` fields — `table` has no time type.
- The migration `0001_init.sql` is the output of `schema.exe migration`; a `diff` rule in `server/sql/dune` fails `dune test` if a table changes without a migration.
- There is no shared `Kre.Db.conn`: services take `Kre.Db.S with type conn = Kre_db_mariadb.Client.t`. Services have no `~conn` either: `Cats.adopt` and `Adoptions.adopt` call `Db.with_conn` and join the handler's transaction.
- `[@@transactional]` is tested with a rollback: the third adoption has already updated the cat, the "2 per member" limit returns `Error` — the cat is available again, and there are no live events.
- `Config.interface` (default `127.0.0.1`): Dream listens on `localhost`, which on macOS is `::1`.
- Tests: `test_shelter` (alcotest via `Dream.test` and `[%wire]`, MariaDB) and `run_scenario` (starts `bin/main.exe` and the Melange client scenario in node: registration, 403, adoption, 409, live `cats`, login page markup). Alias `@examples/shelter/test/shelter`, database `KRE_TEST_SHELTER_URL`; in CI, the `db` job.

Below is the original sketch; the example code is in `examples/shelter`.

### shared — types, the same on both ends

```ocaml
(* user.ml *)
module Email = Kre_shared.Refined.Email
type role = Admin | Member [@@deriving dto]
type t = {
  id    : int;     [@primary] [@auto]
  email : Email.t; [@unique]
  role  : role;    [@default Member]
} [@@deriving table ~name:"users", dto]
(* table emits nothing under melange; dto emits on both *)

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

### server — config, auth, services

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
-- queries/cats.sql  (sqlgg; types checked against schema.sql, built by [@@deriving table])
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

(* cats_service.ml — Kre.Db.conn is the same for all drivers, so the signature does not depend on Db *)
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

(* adoptions_service.ml — a dependency on another service = a functor parameter *)
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

### server — controllers

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
[@@get] [@@live ["cats"]]            (* the frontend refetches when cats changes *)

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
(* Error → rollback + 409; Ok → commit + Live.publish "cats" and "adoptions" (from sqlgg/table writes) *)
```

### bin/main.ml — the whole composition root

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

Forget `(module Users)` and it does not compile. Rename `Cat.name` and `cats.sql` (via `schema.sql`), `Create_cat_dto`, the client and the pages stop compiling.

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

The `/cats` page subscribes to `cats`: while one user views the list and another adopts a cat, the list updates with no subscription code. A 409 error from `[@@transactional]` reaches `Toast.error` as Problem Details.

## Kre.Core — server runtime

The signatures below are the `.mli` files from `src/shared` and `src/core` as built in phase 0; ppx generates code only against them. Nothing that is not listed here gets into the runtime without editing this section.

### Kre\_shared — shared by server and client (native + melange)

```ocaml
(* Kre_shared.Validation — errors and rules *)
module Validation : sig
  type error = { path : string list; rule : string; message : string }
  type t = private { first : error; rest : error list }   (* non-empty set *)
  exception Invalid of t                (* raised by jsonkit decoders; Json.parse catches it *)
  type 'a rule
  val fail : rule:string -> string -> t
  val ok_exn : ('a, t) result -> 'a
  val to_list : t -> error list
  val to_json : t -> Jsonkit.t
  val rule : name:string -> ('a -> ('a, string) result) -> 'a rule
  val check : 'a rule list -> 'a -> ('a, t) result   (* all failed rules, not fail-fast *)
  val field : string -> 'a rule list -> 'a -> ('a, t) result   (* check + path [name] *)
  module Syntax : sig   (* applicative: and+ accumulates the errors of both sides *)
    val ( let+ ) : ('a, t) result -> ('a -> 'b) -> ('b, t) result
    val ( and+ ) : ('a, t) result -> ('b, t) result -> ('a * 'b, t) result
  end
  val min_length : int -> string rule   val max_length : int -> string rule
  val min : int -> int rule             val max : int -> int rule
  val range : min:int -> max:int -> int rule
  val one_of : string list -> string rule
  val email : string rule
end

(* Kre_shared.Asset and Icon — phase 3: values that only [%asset] and [%icon] produce *)
module Asset : sig
  type t
  val checked : string -> t        (* for ppx *)
  val url : t -> string
end
module Icon : sig
  type t
  val checked : name:string -> string -> t   (* for ppx *)
  val name : t -> string
  val svg : t -> string
end

(* Kre_shared.Time — phase 3: a UTC instant; RFC 3339 in JSON and URLs, seconds in the database *)
module Time : sig
  type t
  include Scalar.S with type t := t
  val of_seconds : float -> t
  val to_seconds : t -> float
  val compare : t -> t -> int
end

(* Kre_shared.Page — phase 3: a page of a list *)
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

(* Kre_shared.Search — phase 3: query string ↔ record codec; [@@deriving search] *)
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

(* Kre_shared.Json — the shape that [@@deriving json, jsonschema] from jsonkit produces *)
module Json : sig
  module type S = sig
    type t
    val of_json : Jsonkit.t -> t          (* jsonkit convention: raises *)
    val to_json : t -> Jsonkit.t
    val t_jsonschema : Jsonkit.Jsonschema.t
  end
  val parse : (module J : S) -> Jsonkit.t -> (J.t, Validation.t) result
  module List (J : S) : S with type t = J.t list
end

(* Kre_shared.Scalar — a value that lives both in JSON and in a path/query segment *)
module Scalar : sig
  module type S = sig
    type t
    include Json.S with type t := t
    val name : string                     (* "int", "string", … — in Spec *)
    val of_string : string -> (t, Validation.t) result
    val to_string : t -> string
  end
  module Int : S with type t = int        module Int64 : S with type t = int64
  module Float : S with type t = float    module Bool : S with type t = bool
  module String : S with type t = string
end
```

`Kre_shared.Refined` — see the dto section.

### Kre — server (native)

```ocaml
(* Kre.Error — the single error type: HTTP errors and exception filters *)
module Error : sig
  type status = [ Dream.client_error | Dream.server_error | `Unprocessable_Entity ]
  type t = private {
    status : status; code : string; type_ : string; detail : string;
    extensions : (string * Jsonkit.t) list;   (* extra top-level Problem Details members *)
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

(* Kre.Response — an explicit JSON response; the rest (text, html, redirect, stream) is plain Dream *)
module Response : sig
  val json : ?status:Dream.status -> (module J : Kre_shared.Json.S) -> J.t -> Dream.response Lwt.t
end

(* Kre.Guard — extracts a value from the request: guards and custom parameter extractors *)
module Guard : sig
  type 'a t = Dream.request -> ('a, Error.t) result Lwt.t
  val field : 'a Dream.field -> missing:Error.t -> 'a t
  val header : string -> string t
  val both : 'a t -> 'b t -> ('a * 'b) t
  val session : string -> string t                     (* session field, else 401 *)
  val map : ('a -> 'b) -> 'a t -> 'b t
  val check : ('a -> ('b, Error.t) result) -> 'a t -> 'b t   (* role → evidence *)
  val optional : 'a t -> 'a option t
end

(* Kre.Spec — runtime description of a controller; the source for kre client / kre openapi *)
module Spec : sig
  type verb = [ `GET | `POST | `PUT | `PATCH | `DELETE ]
  type presence = Required | Optional | Repeated
  type location = Path | Query of presence | Header of presence | Cookie of presence
                | Search                       (* phase 3: the whole query string into a record, [@search] *)
  type dto = { name : string; schema : Jsonkit.Jsonschema.t }
  type param = { name : string; location : location; scalar : string; schema : Jsonkit.Jsonschema.t }
  type returns = Unit | Text | Json of value | Events of value | Raw
  type route = {
    verb : verb; path : string; name : string; params : param list;
    body : dto option; returns : returns; status : Dream.status; guards : string list;
    live : string list;                          (* [@@live], phase 2 *)
  }
  type t = { prefix : string; version : int option; routes : route list }
  val to_json : t -> Jsonkit.t
end

(* Kre.Route — what ppx turns a handler into; the logic lives here, not in generated code *)
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

(* Kre.App — assemble and run *)
module App : sig
  type tls = Development_certificate | Certificate of { certificate_file : string; key_file : string }
  val handler : ?middleware:Dream.middleware list -> ?error_handler:Error.handler -> Controller.t list -> Dream.handler
  val run : ?interface:string -> ?port:int -> ?tls:tls -> ?middleware:Dream.middleware list ->
    ?error_handler:Error.handler -> ?on_start:(unit -> unit Lwt.t) -> ?on_shutdown:(unit -> unit Lwt.t) ->
    ?commands:Command.t list -> Controller.t list -> unit   (* argv: a command → run it; otherwise the server *)
end

(* Kre.Etag — phase 3: ETag from the body of a 200 response to GET/HEAD, If-None-Match → 304; [@@etag] *)
module Etag : sig
  val middleware : Dream.middleware
end

(* Kre.Retry — phase 3: retry on exception, the delay doubles; [@@retry n] [@@backoff s] *)
module Retry : sig
  val run : ?backoff:float -> attempts:int -> (unit -> 'a Lwt.t) -> 'a Lwt.t
end

(* Kre.Command — phase 3: binary commands; [@@command "…"] generates, [%wire] collects, App.run ~commands runs *)
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

(* Kre.Job — phase 3: database-backed queues; [@@job q] registers a handler, the worker is provider hooks *)
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
    val dashboard : Controller.t
  end
  module Make (Db : Db.S) (Config : sig val poll : float val attempts : int end) : S
end

(* Kre.Profiler — phase 3: requests and their SQL in dev; /__kre/profiler *)
module Profiler : sig
  type entry = { method_ : string; target : string; status : int; milliseconds : float; queries : string list }
  val sql : string -> unit                 (* drivers *)
  val middleware : Dream.middleware
  val controller : Controller.t
  val recent : unit -> entry list
  val repeated : entry -> (string * int) list   (* N+1 *)
end

(* Kre.Mail — phase 3: emails; Smtp and Outbox providers *)
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

(* Kre.Assets — phase 3: /assets/<name>.<hash>.<extension> with a permanent cache; [%asset] gives the links *)
module Assets : sig
  val middleware : dir:string -> Dream.middleware
end

(* Kre.Signed — phase 3: signed links; [@@signed secret] *)
module Signed : sig
  val url : ?now:float -> secret:string -> expires_in:float -> string -> string
  val guard : ?now:(unit -> float) -> secret:string -> unit -> unit Guard.t
end

(* Kre.Wiring — what [%wire] assembles *)
module Wiring : sig
  type t = private { controllers : Controller.t list; on_start : unit -> unit Lwt.t;
                     on_shutdown : unit -> unit Lwt.t; health : Actuator.check list;
                     commands : Command.t list; beans : Actuator.bean list }
  val make : controllers:Controller.t list -> on_start:(unit -> unit Lwt.t) list ->
    on_shutdown:(unit -> unit Lwt.t) list -> ?jobs:Schedule.job list ->
    ?health:Actuator.check list -> ?commands:Command.t list ->
    ?beans:Actuator.bean list -> unit -> t
  module type ALL = sig type t val all : t list end   (* parameter "all I.S providers" *)
  val profile : unit -> string                       (* KRE_ENV or "dev" — for [@@@profile] *)
end

(* Kre.Token — API tokens; [@@ability "x"] calls Tokens.ability "x" *)
module Token : sig
  val table : Table.t
  type t = private { id : string; owner : string; abilities : string list }
  module type S = sig
    val issue : owner:string -> abilities:string list -> (string * t) Lwt.t
    val tokens : owner:string -> t list Lwt.t
    val revoke : string -> unit Lwt.t
    val current : t Guard.t
    val ability : string -> t Guard.t
  end
  module Make (Db : Db.S) : S
end

(* Kre.Lock — phase 3: locks in the database; [@@lock "name"] calls Lock.exclusive *)
module Lock : sig
  val table : Table.t
  module type S = sig
    val exclusive : ?ttl:float -> string -> (unit -> unit Lwt.t) -> unit Lwt.t
  end
  module Make (Db : Db.S) : S
end

(* Kre.Live — live loaders, phase 2 *)
module Live : sig
  val publish : string list -> unit                        (* stores without SQL *)
  val read : string -> unit                                (* driver: SELECT, to check [@@live] *)
  val wrote : string -> unit                               (* driver: INSERT/UPDATE/DELETE *)
  val deferred : (unit -> ('a, 'e) result Lwt.t) -> ('a, 'e) result Lwt.t   (* Db.transaction *)
  val audit : string list -> Dream.middleware              (* ppx for [@@live] *)
  val subscribe : string list -> string Lwt_stream.t * (unit -> unit)
  val controller : Controller.t                            (* GET /__kre/live?table=… *)
end
```

Deviations from the first version of this section (phase 0) and why:

- `Kre.run`/`Kre.app` → `Kre.App.run`/`Kre.App.handler`: a dune wrapper module cannot contain values without re-exporting its submodules through aliases, and aliases are forbidden.
- `Codec.t` (a record) → `Kre_shared.Scalar.S` modules: one entity for "a value in JSON and in a URL"; `Refined.Make` is built with `include` without aliases, and ppx passes `(module Kre_shared.Scalar.Int)` as a modular explicit.
- `Json.DTO` with `validate` is removed: the check is part of `of_json` (parse, don't validate). All body parsing errors are `Validation.t`; invalid JSON text is 400, field and type errors are 422.
- `Error.t`: the status is limited to 4xx/5xx, `details : Jsonkit.t option` → `extensions` (Problem Details spreads them onto the top level, so it is an object, not an arbitrary value); `Response.t` (an alias of `Dream.response`) and the wrappers over `Dream.html`/`redirect`/`stream` are removed — the "we do not wrap Dream" principle.
- `Spec.param.required : bool` → `location = Path | Query of presence`; `?tls:bool` → the `tls` variant.
- `error_handler` receives the request: Problem Details requires `instance`.
- `Validation.regex` and `Refined.Regex` are deferred: regexes are needed in both modes, but `Str` exists only in native (see open questions).

`App` behaviour: each route is a `Route.t` with a method; `App.handler` builds one `Routes.one_of` per method and matches the path from `Dream.target` without the query. `MatchWithTrailingSlash` → 301 to the path without the slash, with the same query. No route → `error_handler` with `Error.not_found`. All error responses go through `error_handler` (by default `Error.to_response`); `Error.E` from a handler → its status; other exceptions → 500 `internal` and a log entry. Order: global middleware → matching → controller middleware (`[@@@use]`) → handler middleware (`[@@use]`) → guards → parameter parsing → handler body (the request lifecycle). `App.run` calls `on_start`, then `Dream.serve` until SIGINT/SIGTERM, then `on_shutdown`.

## ppx: controller

One global ppxlib transformation (`Driver.register_transformation ~impl`) over the whole structure of a file. It is purely syntactic: it does not see types, so everything needed for generation comes from annotations. Rule: **a handler without a return type annotation is a compile error.**

### Attributes

| Attribute | Where | Payload |
| --- | --- | --- |
| `[@@@controller "cats"]` | first item of the file | prefix string; `""` is allowed |
| `[@@@version 2]` | floating | int → prefix `/v2` (URI mode) |
| `[@@@use [m1; m2]]` | floating | `Dream.middleware list` |
| `[@@@guards [g1; g2]]` | floating | `unit Guard.t list` — they check and discard the value |
| `[@@@inject: module X : S]` | floating | a dependency available to the whole file (for helpers) |
| `[@@get ""]` `[@@post]` `[@@put ":id"]` `[@@patch]` `[@@delete]` | on `let` | path string relative to the prefix; empty/missing = `""` |
| `[@@status 201]` | on `let` | int |
| `[@@use [...]]`, `[@@guards [...]]` | on `let` | like floating, but for one handler |
| `[@@header ("Cache-Control", "no-store")]` | on `let` | pair of strings, repeatable |
| `[@@redirect "/x"]` | on `let` | string (+ optional status) |
| `[@@sse]` | on `let` | none; returns `τ Lwt_stream.t` |
| `[@guard e]` / `[@from e]` | on a parameter | `e : 'a Guard.t`; synonyms |

### Handler shape

```ocaml
let name (module M1 : S1) … (module Mn : Sn)   (* 0..n module parameters — dependencies *)
    ~p1 ?p2 ?(p3 = default) …                   (* labelled/optional — path/query/body/guard *)
    (req : Dream.request)?                        (* optional positional *)
    ()                                            (* required if there are no other positionals *)
    : <return-type> = body
[@@verb path] [@@…]
```

### Parameter classification

In order of checking:

1. The label occurs as `:label` in the full path (prefix + handler path) → **path**. The type annotation is required.
2. Label = `body` → **body**. Type `T.t` (or a list) → module `T : Kre_shared.Json.S`; generates `Kre.Route.body (module T)`: non-JSON → 400, parse and rule errors → 422.
3. The parameter carries `[@guard e]`/`[@from e]` → **guard**: `e req` is evaluated before the body; `Error` → response; it does not appear in `spec` or in the client.
4. Everything else labelled/optional → **query**, the type is required. `?(x : τ option)` and `~(x : τ option)` = optional; `?(x : τ = d)` = optional with a default (the handler applies the default itself, ppx passes `?x`); `~(x : τ)` = required, missing → 400; `~(x : τ list)` → repeatable `?x=a&x=b`.
5. A positional with the annotation `Dream.request` → the raw request. Any other positional, except the final `()`, is an error.

Module selection by type (syntactic): `int → Kre_shared.Scalar.Int`, `int64`, `float`, `bool`, `string` — likewise; `T.t → T` (for path/query `T : Kre_shared.Scalar.S`, for body and result `T : Kre_shared.Json.S`); `τ list` in body/result → `Kre_shared.Json.List (τ)`. Any other type → an error listing the forms. `[@codec e]` is not implemented: custom parsing is a custom `Scalar.S` module (for example, `Refined.Make`).

### Injection from the request: `[@from]` and `Kre.Extract`

Every injection from the request (the raw request, headers, IP, session, host, the whole query, a custom extractor) is one mechanism: a parameter with `[@from e]`, where `e : 'a Guard.t = Dream.request -> ('a, Error.t) result Lwt.t`. The parameter can be labelled (`~ip:(string [@from Extract.ip])`) or **positional** (`(ip : string [@from Extract.ip])`); this refines rule 5 above: a positional parameter is either `Dream.request`, or `()`, or carries `[@from]`.

For a handler with n such parameters, ppx generates n sequential `let*` in the wrapper — the arity is static, and the compiler checks the type of each extraction against the annotation. Extraction order is left to right; the first `Error` stops the chain.

```ocaml
let find_all (module Cats : Cats_service.S)
    (req : Dream.request)                                  (* the raw request *)
    (ip : string [@from Extract.ip])                       (* client IP *)
    (ua : string option [@from Extract.header "user-agent"])  (* one header *)
    (sess : Session.t [@from Auth.session])                (* session / custom extractor *)
    () : Cat.t list Lwt.t = …
[@@get]
```

`Kre.Extract` — standard extractions, in `Core`:

```ocaml
module Extract : sig
  val req     : Dream.request Guard.t
  val ip      : string Guard.t
  val host    : string Guard.t
  val header  : string -> string option Guard.t           (* None if missing *)
  val header_exn : string -> string Guard.t               (* 400 if missing *)
  val headers : (string * string) list Guard.t
  val cookie  : string -> string option Guard.t
  val query   : (string * string) list Guard.t            (* the whole query *)
  val search  : 's Kre_shared.Search.t -> 's Guard.t    (* phase 3: query into a record, [@search] *)
  val params  : (string * string) list Guard.t            (* all path parameters *)
  val body_raw : string Guard.t
  val body_json : Jsonkit.t Guard.t                       (* body without a DTO *)
  val session : string -> string option Guard.t           (* Dream.session_field *)
  val field   : 'a Dream.field -> missing:Error.t -> 'a Guard.t
end
```

A custom extractor is a plain value: `let tenant : Tenant.t Guard.t = fun req -> …`. Combinators in `Guard`: `map`, `both`, `optional : 'a t -> 'a option t`, `with_default`. There is intentionally no way to inject the response object: the response is the return value, and for full control there is `Response.t Lwt.t`.

### Return type

Recognised annotation forms (`τ` — data type, `E` = `Kre.Error.t`):

| Annotation | Serialization | `Spec.returns` |
| --- | --- | --- |
| `unit Lwt.t` | empty response, default status 204 | `Unit` |
| `string Lwt.t` | `text/plain` | `Text` |
| `T.t Lwt.t` | `T.to_json`, `application/json` | `Json ("T", T.jsonschema)` |
| `T.t list Lwt.t`, `T.t option Lwt.t` | JSON array / JSON or 404 | `Json` with a wrapper in the schema |
| `T.t M.t Lwt.t` (phase 3) | container `M.Make (T)`, for example `Cat.t Kre_shared.Page.t` → `Kre_shared.Page.Make (Cat)`; a custom container is a module with `'a t` and `Make (J : Json.S)` | `Json` |
| `(τ, E) result Lwt.t` | as τ; `Error e` → `error_handler` | as τ |
| `Dream.response Lwt.t` | as is | `Raw` |
| `T.t Lwt_stream.t Lwt.t` + `[@@sse]` | `text/event-stream`, one `data: <json>` event per element (`Kre.Route.events`) | `Events` |

A non-`Lwt` return is an error "handler must return … Lwt.t". An annotation that does not match the table is an error listing the forms.

### Dependencies (modular explicits)

The module parameters of all handlers are merged by name. One name with different signatures is an error. The merged list becomes the parameters of `register`, in order of first appearance. Handlers stay as written, with their own modular explicits; `register` calls them as `find_one (module Cats) ~id`. The `Make` functor from the first version of the plan is not needed (phase 1 decision): this means less rewriting, a handler can be called directly in a test, and `[@@@inject]` for helpers is deferred.

### What is generated

The file stays as it was (Kre attributes are removed), and three items are appended at the end. For `cats` with the handler `find_one (module Cats : Cats_service.S) ~(id : int)`:

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

Extractions (query, body, `[@guard]`/`[@from]`) form a chain `let open Kre.Route.Syntax in let* … in`, left to right; the first `Error` stops the chain. A handler without dependencies gives `register ()`. `Paths` functions take `()` so that the path is polymorphic: `Routes.sprintf (Cats_controller.Paths.find_one ()) 42 = "/cats/42"`. A segment path is `Kre.Route.segment (module M) ":name"`: a failure of `M.of_string` is `NoMatch`, i.e. 404. Full reference outputs are in `test/ppx/controller.t`.

`Kre.Route` is a runtime module: `handle` wraps guards, serialization and error mapping; `query`, `body`, `segment`, `ok`, `Syntax.let*` are everything the generated code calls. The generated code contains no logic.

Phase 2: `[@@header (k, v)]` (repeatable, on a successful response), `[@@redirect "/url"]` (handler with `unit Lwt.t`, default status 302), `[@@timeout 5.0]` (`Lwt.pick` with a sleep; on expiry — 504 `timeout`), `[@@@error_handler h]` (`Kre.Error.handler` for the route errors of this controller) — done, example: `docs/examples/legacy_controller.ml`. `[@@@inject]` is not needed: a helper takes a module as a parameter, like a handler. `[@codec e]` is not needed: custom parsing is a custom `Scalar.S` module. `[@@sse]` has a row of its own.

### ppx errors (all via `Location.raise_errorf`, located at the offending node)

- `[@@@controller]` is not the first item; two `[@@@controller]` in one file.
- `[@@get]` on a `let` whose pattern is not an identifier, on `let rec`, on `and`.
- Missing return type annotation; unsupported form.
- A path parameter from the path without a matching label (`":id"`, but no `~id`), and the reverse — the label matches `:x`, but the type is not annotated.
- Two `body` parameters; `body` without a `T.t` type.
- A positional parameter without the `Dream.request` annotation.
- Conflicting signatures of a module parameter.
- `[@@status]` outside 100–599; `[@@sse]` without `Lwt_stream.t`.

Each error is a separate case in the cram test `test/ppx/errors.t` (output of `pp.exe -impl`).

## DI and the other primitives

All primitives of the framework overview are expressed without a container. The table below is normative: each concept is translated this way and only this way.

| Concept | Kre | Mechanism |
| --- | --- | --- |
| Provider (singleton) | a module with `module type S` in `.mli` | state is the module's top-level values |
| Provider with dependencies | functor `Make (Db : Db.S) (Log : Logger.S) : S` | applied in `main.ml` |
| Constructor injection | handler module parameters `(module Cats : Cats_service.S)` | modular explicits → `register` parameters |
| Value, class and factory providers | another module of the same `S`; factory = `let%lwt` in `main` before `Kre.App.run` | — |
| Configurable module | functor with a config module: `Cache.Make (struct let ttl = 60 end)` | — |
| Default (singleton) scope | module | — |
| Request scope | `Dream.field` + `Guard.field` | middleware sets the value, `[@guard]` reads it |
| Transient scope | plain function | — |
| Module declaration (imports, providers, exports) | `main.ml` + `.mli` + dune `(libraries)` | does not exist as an entity |
| Circular dependency / forward reference | compile error | — |
| Middleware | `Dream.middleware`; `[@@@use]` / `[@@use]` / `Kre.App.run ~middleware` | — |
| Middleware with dependencies | `let use (module Log : Logger.S) : Dream.middleware = …` | applied in `[@@@use [Logger.use (module Log)]]` |
| Guard | `'a Guard.t = Dream.request -> ('a, Error.t) result Lwt.t` | `[@guard e]` yields a value; `[@@guards [e]]` only checks |
| Pipe (parse a parameter) | parameter type annotation | `Codec` |
| Pipe (validate the body) | `[@@deriving dto]` → `validate` | automatic on `body` |
| Custom pipe | `[@codec e]` on a parameter / `Codec.custom` | — |
| Interceptor (before/after) | `Dream.middleware` | — |
| Interceptor (transform response) | middleware over `Dream.response` or an explicit `Response.json` | no observable streams |
| Exception filter | `Kre.App.run ~error_handler`; per controller — `[@@@error_handler f]` | `Error.t -> Dream.response Lwt.t` |
| HTTP exception | `Error.t` in `result` or `Error.fail` | — |
| Custom parameter extractor (current user) | `[@from Auth.current]` | any `'a Guard.t` |
| Execution context | positional `(req : Dream.request)` | — |
| Lifecycle hooks (init, shutdown) | `Kre.App.run ~on_start ~on_shutdown` | `Lwt_switch` inside |

### Wiring: `[%wire]` (phase 2)

```ocaml
(* bin/main.ml *)
let () =
  let app = [%wire] in
  Kre.App.run ~on_start:app.on_start ~on_shutdown:app.on_shutdown app.controllers
```

`[%wire]` scans the application directory — the parent of the directory with `main.ml` — recursively, skipping `test`/`tests`, `_build`, `node_modules` and hidden directories; copies of one module (`copy_files#` for Melange) are merged by name. To narrow: `[%wire "server"; "db"]`, paths relative to the application directory. In dune: `(preprocessor_deps (source_tree ..))` — rebuild when sources change. ppx finds the components itself:

| What is in the file | Role |
| --- | --- |
| `module Make () = …` | provider; a new instance (a fresh one on each call by hand) |
| `module Make (Db : Kre.Db.S) (Clock : Clock.S) = …` | provider with dependencies; parameters are constructor injection |
| `module type S` without `Make` | singleton: the module itself is the instance |
| `[@@@controller]` | consumer: handler module parameters → `register` |
| everything else | left untouched |

A provider's interface is the result annotation of `Make` in `.ml` or `.mli` (`: Cats_service.S`, `: sig include Kre.Db.S … end`), otherwise its own `module type S`; explicitly — `[@@@injectable Iface.S]`. A module with only `module type S` (no values and no `Make`) is an interface, not a provider. `[@@@fallback]` is a fallback provider: it is used and created only if there are no other implementations of the interface. If several providers give an interface: the one marked `[@@@primary]`, otherwise the provider whose name matches the functor parameter name (`(Fake_clock : Clock.S)`), otherwise a build error. Build errors with a location: no provider, ambiguity, cycle (`Clock -> Report -> Clock`). The compiler checks dependency types on the generated functor applications.

Hooks: `let on_start` / `let on_shutdown` in a provider (and in its signature) run after the provider is created and before the application stops; start runs in dependency order, shutdown in reverse. `[%wire]` returns `Kre.Wiring.t = { controllers; on_start; on_shutdown; health; commands; beans }`; `beans` is the graph for `/actuator/beans`. Directory modules must be visible from `main` (libraries `(wrapped false)`). Reference outputs: `test/wire/wire.t`; example: `examples/cats/bin/main.ml` (`Settings` → `Database.Make` → `Cats_db_service.Make`).

### Guards — example

```ocaml
(* server/auth.ml *)
let user_field : User.t Dream.field = Dream.new_field ~name:"user" ()

(* middleware puts the user into the request from the session/JWT *)
let session (module Users : Users_service.S) : Dream.middleware = fun next req ->
  (match Dream.session_field req "user_id" with
   | None -> Lwt.return_unit
   | Some id ->
     let%lwt u = Users.find (int_of_string id) in
     Option.iter (Dream.set_field req user_field) u;
     Lwt.return_unit)
  >>= fun () -> next req

(* guard reads it *)
let current : User.t Guard.t = Guard.field user_field ~missing:(Error.unauthorized "login required")

let role r : unit Guard.t = fun req ->
  let%lwt u = current req in
  Lwt.return (Result.bind u (fun u -> if List.mem r u.User.roles then Ok () else Error (Error.forbidden "role")))
```

Usage: `~(user : User.t [@guard Auth.current])` in parameters, ``[@@guards [Auth.role `Admin]]`` on a handler. Order: `[@@@guards]` → `[@@guards]` → `[@guard]` parameters left to right.

### Request-scoped providers

No scope "bubbling": a request-scoped value is a `Dream.field` that middleware fills. A service that needs a request value gets it as a function argument, not a constructor argument. This is deliberate: there are no injection scopes to document, and a class of performance bugs goes away.

## ppx: \[@@deriving dto\]

A deriver on records, variants and aliases; works in native and melange (stdlib ≥ 4.12, no `Js`, no yojson — the same constraints as jsonkit). Covers the Validation and Serialization chapters and part of OpenAPI (Types and parameters, Mapped types).

For `type t` it generates a module of the shape `Kre_shared.Json.S` (phase 0 decision, see "Relation to jsonkit"):

```ocaml
val of_json      : Jsonkit.t -> t      (* jsonkit [@@deriving json] + rules; raises Validation.Invalid *)
val to_json      : t -> Jsonkit.t      (* jsonkit [@@deriving json] *)
val t_jsonschema : Jsonkit.Jsonschema.t   (* jsonkit [@@deriving jsonschema] + constraints *)
```

At the boundary (request body, client response) `Kre_shared.Json.parse (module T) json : (T.t, Validation.t) result` is called. There is no separate `validate`: checking is part of parsing, and after `of_json` the value is already valid.

For `type foo` — the same names with the prefix `foo_` (jsonkit convention: `foo_of_json`, `foo_jsonschema`).

### Recommended path: opaque types (parse, don't validate)

A DTO field must have a type in which an invalid value is unrepresentable. Then `of_json` is the only check point, and the service never receives a "raw" string. `[@validate]` on `string`/`int` is an acceptable escape hatch for one-off rules, but not the main way.

`Kre_shared.Refined` — factories of opaque types, built in `shared/` (implemented in phase 0):

```ocaml
module type S = sig
  type t
  type repr
  include Kre_shared.Scalar.S with type t := t   (* of_json/to_json/t_jsonschema + of_string/to_string: works both in the body and in path/query *)
  val of_repr : repr -> (t, Kre_shared.Validation.t) result   (* smart constructor *)
  val to_repr : t -> repr
  val pp : Format.formatter -> t -> unit
end

module type RULES = sig
  type base
  val name : string                                         (* title in the schema *)
  val rules : base Kre_shared.Validation.rule list
  val constraints : (string * Jsonkit.Jsonschema.t) list    (* minLength, enum, format, … *)
end

module Make (Base : Kre_shared.Scalar.S) (C : RULES with type base := Base.t) : S with type repr = Base.t
module String (C : sig val name : string  val min : int  val max : int end) : S with type repr = string
module Int    (C : sig val name : string  val min : int  val max : int end) : S with type repr = int
module Enum   (C : sig val name : string  val values : string list end)    : S with type repr = string
module Email  : S with type repr = string
(* Regex — deferred: needs a regex engine that works in both native and melange *)
```

Relation to `dto`: a field of type `T.t`, where `T : Json.S`, is encoded via `T.of_json`/`T.to_json`, the schema is `T.t_jsonschema`. This is exactly what the jsonkit deriver calls for a field of type `T.t`, so opaque modules from `Refined` plug into jsonkit records without ppx involvement. Field errors must be collected applicatively (not fail-fast) into one `Validation.t` with paths — for this the jsonkit decoder needs a mode that accumulates errors with paths (open question; until then — the first error, empty path).

Cross-field invariants (password = confirmation, `from < to`) — either an opaque record with its own `of_repr`, or `[@@dto.check f]` on the type, `f : t -> (t, Validation.t) result`, which `of_json` calls last.

### Identifiers: `Kre_shared.Id` (phase 2)

```ocaml
module Id = Kre_shared.Id.Make ()          (* in cat.ml: a distinct type for each entity *)
type t = { id : Id.t; [@primary] [@auto] [@column int] … } [@@deriving table ~name:"cats", dto]
let find_one (module Cats : Cats_service.S) ~(id : Cat.Id.t) : … [@@get ":id"]
```

`Id.Make ()` is a generative functor: a cat id cannot be passed in place of an owner id. `Id.S` is `Refined.S` over `int` (`of_repr` accepts only `≥ 1`) plus `first`, `succ`, `equal`: a value comes from parsing (JSON, path, query, a database row) or from `succ`, so an in-memory service needs no check that can fail. Since `Id.S` is `Scalar.S` and `Json.S`, an id works in the path (`/cats/0` → 404 before the handler), in the body, in `spec`, in `table` and in the client router. The `kre generate controller` template creates a resource with `Id`.

### typegist — phase 0 decision: (b), not used

[typegist](https://github.com/dbuenzli/typegist) represents OCaml types as values, on top of which generic codecs are written. The decision is (b): `dto` does not generate a gist and relies on the jsonkit derivers. Reasons: opam has only `typegist.0.0.0`; it was decided that all JSON is jsonkit, and jsonkit already has `[@@deriving json]` and `[@@deriving jsonschema]` on both backends, so `dto` reduces to a thin layer on top (rules, `[@exclude]`, `[@expose]`), and a gist would duplicate jsonkit. Revisit if generic derivations are needed that jsonkit does not have (QuickCheck generators, diffs).

### How dto works (phase 1)

`dto` is a preprocessing transformation (`Driver.register_transformation ~preprocess_impl ~preprocess_intf`); it runs before the derivers. `[@@deriving dto]` is rewritten to jsonkit's `[@@deriving json, jsonschema]`; `~strict` adds `[@@disallow_extra_fields]`. Field attributes are not renamed: ppxlib matches an attribute by name suffix, so `[@key]` and `[@default]` are seen by both jsonkit derivers (`json.key` and `jsonschema.key`). If fields have `[@validate]`, a wrapper is added after the type that overrides jsonkit's `of_json`:

```ocaml
let of_json __kre_json =
  let __kre_value = of_json __kre_json in
  Kre_shared.Validation.ok_exn
    (let open Kre_shared.Validation.Syntax in
     let+ __kre_name = Kre_shared.Validation.field "fullName" [ Kre_shared.Validation.(max_length 8) ] __kre_value.name
     and+ __kre_tag = … in
     { __kre_value with name = __kre_name; tag = __kre_tag })
```

`and+` accumulates the errors of all fields; the path is the field's JSON key. For fields of primitive types, `open Jsonkit.Primitives` must be in scope (a jsonkit requirement). The user's `shared/` uses `(pps jsonkit.ppx kre-ppx)` in native and `(pps melange.ppx jsonkit-melange.ppx kre-ppx)` in melange. Reference outputs: `test/ppx/dto.t`.

### Field attributes

| Attribute | Effect |
| --- | --- |
| `[@key "camelName"]` | name in JSON (jsonkit `json.key`/`jsonschema.key`) |
| `[@default e]` | the field is optional in JSON, default when missing (jsonkit) |
| `[@validate r1; r2]` | rules `'a Kre_shared.Validation.rule`, applied in order, errors of all rules are collected |
| `[@validate.custom f]` | `f : t_field -> (t_field, string) result` → `Validation.rule ~name:"custom" f` |
| `[@exclude]` | not serialized in `to_json`; `of_json` requires `[@default]` — phase 2 |
| `[@expose ~groups:["admin"]]` | serialized only with `to_json ~groups` — phase 2 |
| `[@nested]` | not needed: a nested DTO is checked by its own `T.of_json` |

Validation rules are plain values `Kre_shared.Validation.*`; ppx only calls them and collects `{ path; rule; message }`. New rules are added to the runtime, not to ppx.

### Deriver options

| Option | Effect |
| --- | --- |
| `[@@deriving dto]` | everything above |
| `[@@deriving dto ~partial_of:T]` | type = all fields of `T.t` as `option`; `validate` applies the rules of `T` to the present fields |
| `[@@deriving dto ~pick_of:(T, ["name"; "age"])]` / `~omit_of` | a subset of the fields of `T` |
| `[@@deriving dto ~strict]` | unknown fields in JSON → 422; in the schema `additionalProperties: false` |

`~partial_of`/`~pick_of` require `T` to be declared in the same file or `T.t` to be visible to ppx as a record — implemented via `[@@deriving dto]` on `T`, which additionally emits `__dto_fields_T` (the list of fields with schemas) for reuse. This is phase 2; phase 1 has only the base `dto` and `~strict`.

### Variants

| Form | JSON |
| --- | --- |
| `A \| B` (no arguments) | `"a"`: the module becomes `Scalar.S` (`of_string`/`to_string`, JSON Schema `enum`) — usable for path, query and `[@column string]`; `[@key "x"]` on a constructor changes the string |
| `A of int` | `{"tag":"A","value":1}`; `[@@dto ~tag:"type" ~content:"data"]` changes the keys |
| `A of { x : int }` | `{"tag":"A","x":1}` |
| `t option` | `null` / value |

### Behavior on a request body error

The body does not parse as JSON → `Error.bad_request` (400). There is JSON, but `Json.parse` returned `Error errors` (wrong type, missing field, rule violated) → `Error.unprocessable errors` (422), Problem Details:

```json
{ "type": "urn:kre:error:validation", "title": "Unprocessable Entity", "status": 422,
  "detail": "validation failed", "instance": "/cats",
  "errors": [ { "path": ["age"], "rule": "range", "message": "must be between 0 and 40" } ] }
```

The client side (`Kre_client.Error`) parses this format; `errors` are available to the form component in typed form.

### Relation to jsonkit (decided in phase 0)

`dto` **does not duplicate** jsonkit: all JSON in Kre is jsonkit. jsonkit 1.1.0 (opam) already has `[@@deriving json]` (`of_json`/`to_json`, raising `Jsonkit.Of_json_error`) and `[@@deriving jsonschema]` (`t_jsonschema`) — both in native (`Jsonkit.t = Yojson.Basic.t`) and in melange (`Jsonkit.t = Js.Json.t`); `Jsonkit.Jsonschema.t` is the same polymorphic variant on both. Therefore:

- `Kre_shared.Json.S` follows the shape of the jsonkit derivers (`of_json` raises, the schema name is `t_jsonschema`), and any type with `[@@deriving json, jsonschema]` is already a `Json.S`.
- The "exception → result" boundary is one function, `Json.parse`; it also turns `Jsonkit.Of_json_error` into a `Validation.t` with the rule `type`.
- The contribution of `dto` itself is `[@validate]` rules, `[@exclude]`/`[@expose]`, `~strict`; accumulating errors with paths is an improvement to jsonkit, not to Kre.
- jsonkit ships as two libraries (`jsonkit`, `jsonkit-melange`), so code that builds in both modes is two dune libraries with the same `name` from the same sources (`copy_files#`). This is how `kre.shared` / `kre-client.shared` is set up; `kre new` will generate the user project's `shared/` the same way.
- Variant encoding follows jsonkit (`["A", 1]`); the "Variants" table above will be aligned with it when `dto` is implemented in phase 1.

## ppx: \[@@deriving config\]

A typed config from environment variables, checked at startup. Configuration reduces to a single record: no config module and no separate schema library.

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

Generates:

```ocaml
val load     : ?env:(string -> string option) -> unit -> (t, string list) result
  (* all errors at once: ["DATABASE_URL: missing"; "PORT: not an int: 'abc'"] *)
val load_exn : ?env:(string -> string option) -> unit -> t   (* prints the list and exits 1 *)
val pp       : Format.formatter -> t -> unit                 (* [@secret] is printed as *** *)
```

Supported field types: `int`, `int64`, `float`, `bool` (`true/1/yes`, `false/0/no` — `Kre.Config.Flag`), `string`, `T.t` with `T : Kre_shared.Scalar.S` (for example, `Refined.Email.t`), `τ option` (missing = `None`, `[@default]` is forbidden), `τ list` with `[@sep ","]` (one character). The variable name without `[@env]` is the field name in upper case. Nested records with `[@prefix "DB_"]` — phase 2.

Implementation (phase 1) is an interpreter: for each field a `'a Kre.Config.field` description is generated, `load` reads all fields via `Kre.Config.read` and `and+` (errors accumulate), `pp` prints `NAME=value` one per line via `Kre.Config.show`, `[@secret]` is `Kre.Config.secret field`, printed as `***`. Reference output: `test/ppx/config.t`.

```ocaml
(* Kre.Config — runtime of [@@deriving config] *)
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
val dotenv : ?env:env -> string list -> env          (* .env layers under the real environment *)
val profile : ?dir:string -> ?env:env -> unit -> env  (* config/default.env, then config/$KRE_ENV.env *)
module Syntax : sig val ( let+ ) : … val ( and+ ) : … end
module Flag : Kre_shared.Scalar.S with type t = bool
```

`.env` files do not change the process environment (`putenv` is not used): `dotenv`/`profile` return a lookup function that is passed to `load ~env`. Order: real environment → last file → … → first file; a missing file is skipped; lines `KEY=VALUE`, `export KEY=VALUE`, quotes and `#` comments.

## Data: Db, sqlgg, \[@@deriving table\], migrations

No ORM. One Data chapter: queries are sqlgg, the schema is `table`, migrations are `kre migrate`.

### Kre.Db

Implemented in phase 1. sqlgg already contains traits for MariaDB (`sqlgg.mariadb`: `Sqlgg_mariadb.Make (IO) (Mariadb.Nonblocking.S) (Types)`), so `Kre.Db` does not implement traits; it provides a pool and transactions. Queries are sqlgg modules applied to the driver's traits.

```ocaml
(* Kre.Db — in the core, no C dependencies *)
module type DRIVER = sig
  type conn
  val connect : string -> conn Lwt.t
  val close : conn -> unit Lwt.t
  val start : conn -> unit Lwt.t
  val commit : conn -> unit Lwt.t
  val rollback : conn -> unit Lwt.t
  val query : conn -> string -> string option list -> string option list list Lwt.t   (* phase 3: ? → $n for Postgres *)
end
module type S = sig
  type conn
  val query : string -> string option list -> string option list list Lwt.t   (* via with_conn: inside a transaction, runs in it *)
  val with_conn : (conn -> 'a Lwt.t) -> 'a Lwt.t                              (* Lwt_pool; inside a transaction, its connection *)
  val transaction : (conn -> ('a, 'e) result Lwt.t) -> ('a, 'e) result Lwt.t  (* Ok → commit; Error/exception → rollback; inside another one, joins it *)
end
module Make (Driver : DRIVER) (Config : sig val url : string val size : int end) : S with type conn = Driver.conn

(* Kre_db_mariadb — separate package kre-db-mariadb (C bindings) *)
module Client : Mariadb.Nonblocking.S with type 'a future = 'a Lwt.t
module Sql : Sqlgg_traits.M_io with type 'a connection = Client.t and type 'a IO.future = 'a Lwt.t
                                and type Types.Int.t = int64 and type Types.Text.t = string
                                and type Types.Bool.t = bool and type Types.Float.t = float
module Driver : Kre.Db.DRIVER with type conn = Client.t      (* mariadb://user:pass@host:port/db?socket=… *)
```

A service with a database is a functor: `module Make (Db : Kre.Db.S with type conn = Kre_db_mariadb.Client.t) = struct module Sql = Cats_sql.Make (Kre_db_mariadb.Sql) … end`. `Kre_db_pgx` is phase 2.

Implicit transactions (phase 2): `transaction` puts its connection into an Lwt key (`Lwt.with_value`), a value local to the current chain of promises. Everything that runs inside it, `with_conn` of any service and a nested `transaction`, takes this connection instead of a new one from the pool. So services do not need `~conn` in their signature to take part in a controller's transaction. A nested transaction is part of the outer one: the outer one decides commit or rollback, and live events go out once, after its commit. The cost: inside a transaction, queries run one at a time over one connection, and an `Lwt.async` started inside inherits the connection, so background work is started after the transaction.

Postgres (phase 2): the driver is `Kre_db_postgresql` on libpq (the `postgresql` package), not pgx. Reason: sqlgg traits require `execute_response.affected_rows`, and pgx reads the number of changed rows but does not expose it; libpq does (`cmd_tuples`). libpq queries go through `Lwt_preemptive.detach`: the libpq socket is an `int`, and it cannot be turned into a `Unix.file_descr` without `Obj.magic`. sqlgg limitations for `-dialect postgresql`: no `RETURNING`, `BIGSERIAL`, `GENERATED … AS IDENTITY`. So a `[@primary] [@auto]` key is `SERIAL`, and the driver fills `insert_id` with `SELECT lastval()` on the same connection, so services are written the same way for both databases. `Kre.Table.schema` takes a dialect: Postgres has `DOUBLE PRECISION` and a separate `CREATE INDEX`; CRUD queries are shared.

### sqlgg

The `table` + sqlgg pair is Kre's flagship feature: **the schema is an OCaml type, and the compiler checks every SQL query against it.** The chain:

1. `[@@deriving table]` on a record generates `schema : Kre.Table.t`, and a dune rule writes `schema.sql` (DDL for the chosen dialect) from all such types.
2. sqlgg takes `schema.sql` + user queries (`queries/*.sql` or inline via `ppx_sqlgg`) and generates typed functions; nullability is inferred by the fork's lattice analysis and matches `option` in the records.
3. Query results are mapped to records through the `of_row` that `table` generates (by column name), so `SELECT id, name FROM users` → a `User.t`-compatible type with no manual mapping.
4. `kre migrate diff` compares the same `schema` with a snapshot and prepares a draft migration.

Effect: rename the `email` field in a record, and the DTOs, the client, the frontend loader **and every SQL query that mentions it** stop compiling, while `kre migrate diff` proposes an `ALTER TABLE`. No layer learns about the mismatch at runtime.

Example query (sqlgg, file `queries/users.sql`):

```sql
-- @find_adults_by_breed
SELECT u.id, u.email, u.name, u.age
FROM users u JOIN cats c ON c.owner_id = u.id
WHERE c.breed = @breed AND u.age >= @min_age
```

generated signature (with `Kre.Db` as the sqlgg traits):

```ocaml
val find_adults_by_breed : Db.conn -> breed:string -> min_age:int -> User.t list Lwt.t
```

Use in a service is a plain call; the controller does not see it. Kre adds three things here: `Kre.Db` implements the sqlgg traits (IO = Lwt, parameters, rows); `table` emits `schema.sql` and `of_row`; the `kre new` template contains dune rules for the whole chain. sqlgg itself is not forked further and not wrapped.

### \[@@deriving table\]

Implemented: DDL and `of_row` (phase 1); CRUD (phase 2): `Kre.Table.crud` prints SQL, sqlgg generates a module, the deriver provides `for_insert`/`for_update`. A single shared `spread` is impossible: labels cannot be reordered on a parameter without a type annotation, and in sqlgg `update` puts the key last while `insert` does not take it.

```ocaml
type t = {
  id : int; [@primary] [@auto]
  name : Name.t; [@column string] [@size 64]
  age : Age.t; [@column int]
  breed : Breed.t; [@column string] [@size 32] [@index]
}
[@@deriving table ~name:"cats", dto]
(* → table : Kre.Table.t
     of_row : id:int64 -> name:string -> age:int64 -> breed:string -> t   (shape of the sqlgg callback) *)
```

- Column types: `int`/`int64` → `BIGINT`, `string` → `VARCHAR(size)` or `TEXT`, `bool` → `BOOLEAN`, `float` → `DOUBLE`, `τ option` → `NULL`. A field of an abstract type `T.t` (`Refined`) requires `[@column int|string|bool|float]`: the ppx does not see the representation of `T.t`, and the argument type of `of_row` must match what sqlgg provides; the value goes through `T.of_string` (`Kre.Table.decode`), so `Refined` rules are also checked when reading from the database. Time is `Kre_shared.Time.t` (phase 3, no `[@column]`): `DOUBLE` seconds in the database, RFC 3339 on the wire; not `Ptime` and not `TIMESTAMP`, because the type is also needed in Melange, and sqlgg types `TIMESTAMP` differently in MySQL and Postgres.
- Attributes: `[@primary]`, `[@auto]` (only with `[@primary]`), `[@unique]`, `[@index]`, one role per field; `[@size n]`; `[@references M]` → `FOREIGN KEY … REFERENCES <M.table> (id)`; `[@sql.default "SQL"]`, not `[@default]`, because `[@default]` already means the jsonkit deriver's default (an OCaml value, not SQL).
- `[@created_at]`, `[@updated_at]` (a `Kre_shared.Time.t` field) and `[@version]` (`int`) are phase 3: creation and update timestamps and optimistic locking. `for_insert` sets both timestamps to `Kre.Table.now ()` and the version to 0; `for_update` updates `updated_at`, leaves `created_at` alone and passes the version that was read; `crud` prints `UPDATE … SET …, version = version + 1 WHERE id = @id AND version = @version`. 0 changed rows means the record was changed after it was read: the service responds 409 (`examples/shelter/server/cats_service.ml`, `rename`). Until the examples are released, `0001_init.sql` is regenerated; after release, migrations are only added (`kre migrate diff` is phase 3).
- `Kre.Table.schema [ Cat.table; … ]` prints DDL (MariaDB/MySQL). There is no registry: a small binary with the list of tables builds `schema.sql`, and a dune rule passes it to sqlgg (`examples/cats/db/dune`): `sqlgg -dialect mysql -gen caml_io -name Make schema.sql queries/cats.sql`.
- Under Melange (`(pps … kre-ppx -- -melange)`) `table` generates nothing; `dto` on the same type works.
- Tested on a live MariaDB 11.8: `examples/cats/db` (insert through the controller, read with `Sql.List.all conn ~limit Cat.of_row` and `Sql.Single.by_id`, transaction rollback); alias `dune build @examples/cats/db/test/db` with `KRE_TEST_DB_URL`.

### Migrations

Phase 1 (implemented): `migrations/NNNN_name.sql` with `-- migrate:up` and `-- migrate:down` sections; a statement ends with `;` at the end of a line, and `--` comment lines are skipped. Applied versions are in the `kre_migrations (version, applied_at)` table, which is created on first access.

```ocaml
(* Kre.Migration — on top of the same Kre.Db.DRIVER (it has execute and strings) *)
type t = private { version : string; up : string list; down : string list }
type state = Applied | Pending
val parse : version:string -> string -> (t, string) result
val load : string -> (t list, string) result             (* directory, by file name *)
val create : dir:string -> string -> string              (* next NNNN_name.sql *)
val status : (module D : Db.DRIVER) -> D.conn -> t list -> (t * state) list Lwt.t
val up : (module D : Db.DRIVER) -> D.conn -> t list -> t list Lwt.t        (* all pending, in order *)
val down : (module D : Db.DRIVER) -> D.conn -> t list -> t option Lwt.t    (* the last applied one *)
```

In an application, migrations are embedded in the binary: `Kre.Migration.of_files [%embed_dir "migrations"]`. The `[%embed_dir]` ppx expands to a list of `(file, contents)` at build time (dune: `(preprocessor_deps (glob_files migrations/*.sql))`), so the server does not depend on the working directory. CLI: `kre migrate up|down|status --url URL --dir migrations` (`--url` or `DATABASE_URL`), `kre migrate new NAME`. MariaDB commits DDL implicitly, so a migration with several statements is not atomic: on a failure midway the database stays in an intermediate state and the version is not recorded. Tested on MariaDB (`examples/cats/db/test`, alias `@db`): empty database → `up` → schema in place → `down`, plus the same steps through the CLI.

Phase 3: `kre migrate diff` compares the `schema` of all `table` types with a snapshot and generates a draft SQL that the developer edits by hand; sqlgg already has `-diff`/`-migrate`, check those first. Applying a diff automatically without review: never.

## Client and OpenAPI generation from spec

The contract lives in the controller; `spec` is its runtime reflection; everything else is code generation from `spec`. There is no separate "contract file" that could drift from the code.

### Chain

1. The ppx emits `spec : Kre.Spec.t` into every controller.
2. `Kre.App.run` receives the list of controllers, and with it all the `spec`s, so no separate registry is needed.
3. With the `--emit-spec FILE` flag (a JSON array of `Spec.to_json`) or `--emit-openapi FILE`, `App.run` writes the file and does not start the server; `kre` reads the array back with `Spec.of_json`.
4. `kre client --spec spec.json --out client/gen/` writes melange modules; a dune rule in the project template runs steps 3–4 automatically:

```
(rule (targets spec.json) (deps %{exe:../bin/main.exe})
      (action (run %{exe:../bin/main.exe} --emit-spec spec.json)))
(rule (targets cats_client.ml) (deps spec.json)
      (action (run kre client --spec spec.json --controller cats --out cats_client.ml)))
```

### Generated client

One module `<prefix>_client` per controller (`kre client --spec spec.json --controller cats --out cats_client.ml`). Reference output for cats:

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

Rules: path parameters → `~name`, query `Required`/`Repeated` → `~name`, `Optional` → `?name`, body → `~body`; `()` at the end if there are no parameters or some are optional. Guard parameters do not go into the client. Types are not printed: the compiler infers them from the modules in `spec` (`value.module_`), so DTOs must live in `shared/`. The path is built from segments (`Wire.segment` encodes), without the routes library: it does not build under Melange.

**The same generated file** compiles against two libraries with the same name `Kre_client`: `kre-client` (Melange, `fetch`, `Js.Promise.t`) and `kre-client.native` (cohttp, `Lwt.t`). No `--target` flag is needed. The native variant is used in e2e: `examples/cats/client_native` generates the client with a dune rule from `main.exe --emit-spec` and runs it against a live server.

### Kre\_client.Http and Wire

```ocaml
(* shared by both backends *)
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
(* one per backend; promise = Js.Promise.t or Lwt.t *)
module Http : sig
  val base_url : string ref                       (* "" = same origin; ?base on request is phase 3, [%http_client] *)
  val headers : (string * string) list ref        (* auth, csrf — simplified interceptors *)
  val request : Wire.verb -> path:string list -> ?query:(string * string) list list -> ?body:string ->
    'a Wire.returns -> ('a, Error.t) result promise
  (* native only, phase 3: where requests go *)
  type exchange = { verb : Wire.verb; target : string; headers : (string * string) list; body : string option }
  type transport = Network | Local of (exchange -> Wire.response Lwt.t)
  val transport : transport ref
end

(* kre-client.testing — phase 3; in-process tests through the typed client *)
module Kre_testing : sig
  val use : ?middleware:Dream.middleware list -> Kre.Controller.t list -> unit   (* transport := Local (App.handler …) *)
end
```

A test calls the same generated functions as the frontend (`Cats_client.create ~body`), but without a socket: `Kre_testing.use` replaces the transport with the application handler in the same process. A mistake in the path, body or response type is a compile error in the test, not a 400 at runtime; example: `examples/cats/client_native/test_in_process.ml`.

### OpenAPI

`--emit-openapi` (and `kre openapi --spec`) builds a 3.1 document with `Kre.Openapi.document ~title ~version specs`: `paths` from `spec.routes`, `components.schemas` from the `jsonschema` of every DTO encountered (module name = schema name), `parameters` from `Codec.schema`, `responses` with the code from `status` and the error envelope for 4xx. Tags are controller prefixes. Operation descriptions are the `[@@summary "…"]` and `[@@description "…"]` attributes on the handler; they go into `Spec.route` and OpenAPI. Docstrings are not used, because the code rules forbid comments above functions. DTO schemas with a simple module name (`Cat`) go into `components.schemas` and are referenced with `$ref`; the rest (`Kre_shared.Scalar.Int`, `Kre_shared.Json.List (Cat)`) are inlined. Errors are a `default` response `application/problem+json` with the `Problem` schema. The cats document passes `openapi-spec-validator` (a CI step). Swagger UI is phase 2.

## Frontend: Kre\_client and typed router

A route is a value with `params`/`search`/`data` types, the compiler checks `Link` and `navigate`, the loader is on the route, layouts nest. React is through reason-react, markup is `.mlx`.

### Kre\_client.Router

Implemented in phase 1 (`src/client/router.ml`):

```ocaml
type parent                                         (* layouts around routes *)
type ('p, 's, 'd) route
type any = Any : ('p, 's, 'd) route -> any
type t

val root : ?layout:(children:React.element -> React.element) -> unit -> parent
val nest : parent -> layout:(children:React.element -> React.element) -> parent
val no_data : 'p -> 's -> unit Js.Promise.t
val child :
  ?live:string list ->                              (* phase 2: rerun the loader on /__kre/live *)
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

Differences from the first version (phase 1):
- `?search` and `?loader` "defaulting to unit" cannot be typed in OCaml (an optional argument cannot change the result type), so they are required: `~search:Kre_shared.Search.none`, `~loader:Kre_client.Router.no_data`.
- Route paths are absolute; the parent (`parent`) provides only layouts. Parent parameters are not inherited: the `params` record describes the whole path.
- `link` is a function, not a polymorphic component: a mistake in `params` is a type error at the call site (`test/router/link.t`).
- Matching goes top to bottom through the `make` list; an unparsed `search` counts as no route (`not_found`). The loader is called in `useEffect` when the URL changes; a response for a stale URL is dropped by key. Loader cache, `preload`, `use_params`/`use_search`/`use_loader_data`, `on_error` are phase 2.
- The URL is read through `ReasonReactRouter.useUrl`; `?server_url` is for server-side rendering.

### Path, Search, Params — ppx in kre-ppx

The routes library does not build under Melange, so `Kre_client.Path` is our own: a segment template + `decode`/`encode` to an association list. The path and the parameter type are declared together so that the ppx can check the names:

```ocaml
type params = { id : int } [@@deriving params ~path:"/cats/:id"]   (* → params_path : params Kre_client.Path.t *)
type search = { limit : int; [@default 20] breed : string option } [@@deriving search]   (* → search_codec : search Kre_shared.Search.t *)
let index = Kre_client.Router.child root ~path:[%path "/cats"] ~search:search_codec …   (* [%path] — only without parameters *)
```

`params`: one field for every `:name` and vice versa, otherwise an error listing the mismatches; field types are `Scalar.S`. `search`: `τ option` is optional, `τ list` is repeated, `[@default e]` has a default, otherwise required; parse errors are `Validation.t` with path `[name]`. The types are the same `Kre_shared.Scalar` as in the server and the API client.

### Why the controller does not take the page router's path (decided after phase 1)

We considered `[@@get Cat_routes.params_path]` with a `Path` shared by server and frontend and a handler `~(params : Cat_routes.params)`. Not doing it:

- There is almost no duplication for it to remove. The API client is already generated from the controller's `spec`. Only the page and API paths coincide, but they are different things: in a real application the API moves under `/api` or `/v2`, and pages are named for the user's convenience.
- The ppx would stop seeing path segments in the source text. Checking `:id` against the parameter, `Paths` on routes and `spec` would have to move to runtime, while now all of it is checked at compile time.
- The handler would take a record instead of labels (`~id`), unlike every other handler. We would need two matching implementations or give up the routes trie on the server.

String paths in the controller are already typed: the ppx builds `Routes.path` from the string and the label types, and `Cats_controller.Paths` provides typed values for links and tests. Revisit the question if a real case appears where the page path and the API path must coincide.

### Components

`Link` is a plain reason-react component over `Router.link`; `.mlx` syntax gives `<Link route=… params=… search=…>`. A mistake in `params` is a type error in the component, not at runtime.

JSX is written only in `.mlx`: the dialect is enabled in `dune-project` (`mlx-pp` for the build, `ocamlformat-mlx` 0.29.0.1 for `@fmt`); there are no hand-written `[@JSX]` or `React.createElement` in the examples or in `src/client/router.mlx`.

### What we do not do

File-based routing (one file per route, the path taken from the file name) is not needed: a tree of values gives the same result without code generation from the file system. SSR of Melange components is out of scope; server HTML is Dream eml/tyxml as an option.

## Testing

Four levels, each its own directory in `test/`. No special testing module is needed: replacing a dependency is applying the functor/`register` to a different module.

| Level | Tool | What it checks |
| --- | --- | --- |
| ppx | cram on the output of `pp.exe -impl` | every transformation: reference generated code; every ppx error is a separate test with the expected message |
| core | alcotest | `Error.to_response`, `Codec`, `Validation`, `Refined`, `Spec.to_json`, the OpenAPI generator, `Route.handle` with a substituted request |
| controllers (unit) | alcotest + `Dream.test` | `Cats_controller.register (module Fake_cats)` → `Kre.App.handler` → `Dream.test handler (Dream.request ~method_:`GET \~target:"/cats/1" "")\` → status/body |
| e2e | alcotest, running `examples/cats` | server on a random port; the generated native client (the same generator with `--target native` over cohttp) hits every route; OpenAPI is validated against the 3.1 schema |

Example unit test of a controller with a fake service:

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

The client router is tested in node through melange: `Path` matching and `Search` round-trip are property tests (`Search.parse (Search.print s) = Ok s`). If typegist is adopted, the generators for property tests come from gist.

## CLI kre

A cmdliner binary. Generators write files from templates taken from `examples/cats`; they do nothing "magically", only the files the developer would write by hand anyway.

| Command | Does |
| --- | --- |
| `kre new NAME` | dune-project, 4 directories, cats example, CI, `.ocamlformat`, opam files |
| `kre generate controller cats` | `server/cats_controller.ml` with `[@@@controller]` and a CRUD skeleton, `shared/cat.ml`, `shared/create_cat_dto.ml` |
| `kre generate service cats` | `server/cats_service.ml` + `.mli` with `module type S` |
| `kre generate dto name` | `shared/name_dto.ml` |
| `kre client --spec --out [--target melange\|native]` | typed clients from spec |
| `kre openapi --spec --out` | OpenAPI 3.1 JSON; same as `main.exe --emit-openapi` |
| `kre migrate up\|down\|status\|new NAME` | SQL migrations (phase 1), `diff` (phase 3) |
| `kre routes` | route table from spec |
| `kre start [--watch]` | `dune build -w` + restart of `main.exe`; melange rebuild also through dune |

`kre routes`, `kre openapi` and `kre client` read the `spec.json` that the server binary writes (`--emit-spec`), so there is one serialization of `spec`. Templates are files `src/cli/templates/<new|controller|service|dto>/…/*.tmpl` (`data_only_dirs`); at build time `embed.exe` embeds them in the binary. Substitutions are `{{name}}`, `{{plural}}`, `{{Plural}}`, `{{singular}}`, `{{Singular}}`, and in paths the words `plural`/`singular`; the singular is the name without the trailing `s`. `kre new` has no client and no database yet: `shared/` (native + melange), `server/` with a health controller, `bin/main.ml`, a test; `generate controller` makes a whole resource (type and DTO in `shared/`, in-memory service, controller, test in `test/<plural>/`), and the developer adds the registration in `main.ml` by hand. No overwriting: if even one file exists, nothing is written.

## Errors, transactions and actuator

Five features on top of controllers and DI: a standard error format, authorization, transactions, runtime introspection and environment profiles. All five are compile-time ppx rewriting, not runtime proxies, so a call from inside the same module behaves the same as a call from outside.

| Feature | Kre | Phase |
| --- | --- | --- |
| Problem Details (RFC 9457, `application/problem+json`) | format of `Error.to_json` and of the client `Error.t` | 0 |
| Authorization over the request data ("the user owns this `id`") | `[@@authorize f]` — a typed function over the extracted parameters | 2 |
| Declarative transactions | `[@@transactional]`; the connection is implicit via an Lwt key (or explicit `[@from Db.tx]`) | 2 |
| Actuator: health, info, metrics, routes | `Kre.Actuator.routes` | 2 |
| Profiles | `KRE_ENV` + `config/*.env` layers — done | 1 |

### Problem Details — replaces the error envelope

This format **replaces** the error JSON described in the Core and dto sections. `Error.t` stays the same; the serialization changes:

```json
{ "type": "urn:kre:error:validation", "title": "Unprocessable Entity", "status": 422,
  "detail": "validation failed", "instance": "/cats",
  "errors": [ { "path": ["age"], "rule": "range", "message": "must be between 0 and 40" } ] }
```

`type` = `urn:kre:error:<code>` (overridden with `Error.make ~type_`), `instance` = `Dream.target`, `details` are spread as top-level extensions. Content-Type `application/problem+json`. `Kre_client.Error` parses exactly this.

### `[@@authorize]`

Implemented in phase 2. The closure is called after all parameters are parsed (path, query, body, `[@from]`) and before the body; it receives the handler arguments with the same labels.

```ocaml
let read ~(user : string [@guard Roles.user]) ~(id : int) : string Lwt.t = …
[@@get ":id"] [@@authorize fun ~user ~id -> owns ~user ~id]
```

- The payload is a literal function `fun ~a ~b -> …`: ppx uses the labels to decide what to pass. A label the handler does not have is a compile error; the compiler checks the type.
- The result is only `(unit, Kre.Error.t) result Lwt.t`; the `bool Lwt.t` variant from the first version is removed (boolean blindness). `Error e` becomes the response (usually 403).
- The handler's dependencies are available to the closure by name: it is generated inside `register`, where the modules are already bound.

Difference from `[@@guards]`: a guard sees only the request; `authorize` sees the typed parameters. Example — `docs/examples/notes_controller.ml`.

### `[@@transactional]`

Implemented in phase 2:

```ocaml
let adopt (module Adoptions : Adoptions_service.S)
    (module Db : Kre.Db.S with type conn = Kre_db_mariadb.Client.t)
    ~(user : User.t [@guard Auth.current]) ~(body : Adopt_dto.t)
    : (Adoption.t, Kre.Error.t) result Lwt.t =
  Adoptions.adopt body.cat_id user.id
[@@post] [@@transactional]
```

The connection is not visible in the code: services inside use the usual `Db.with_conn` and join the transaction (see "Kre.Db"). There is no need to open a transaction by hand and pass the connection down.

`Kre.Db.S` gained `tx : conn Guard.t` (reads the connection from a request field) and `within : Dream.request -> (unit -> ('a, Error.t) result Lwt.t) -> ('a, Error.t) result Lwt.t` (opens a transaction or joins the open one, puts the connection in the field, `Ok` → commit, `Error`/exception → rollback). ppx takes the module from the handler's single `Kre.Db.S` dependency, or from the `[@from M.tx]` parameter if there is one (then the connection arrives explicitly as a parameter, as in `examples/cats/db/batch_controller.ml`), and wraps parameter parsing and the handler call in `M.within`; guards run before the transaction. `[@@transactional]` without a `Kre.Db.S` dependency, with two such dependencies and no `[@from M.tx]`, and `[@from M.tx]` without `[@@transactional]` are compile errors. Isolation options and `read_only` — when needed. Example — `examples/shelter/server/adoptions_controller.ml`; tests — the `@db` and `@shelter` aliases.

### Actuator

`Kre.Actuator.routes : config:(module Config.S) -> ?metrics:bool -> unit -> Kre.Controller.t`, mounted as an ordinary controller under `/actuator`:

| Path | Contents |
| --- | --- |
| `/health` | `{"status":"up","checks":{"db":"up"}}`; checks are registered with `Actuator.check ~name f` |
| `/info` | version, git sha, build time (from dune `%{version}` and `git describe` in the build) |
| `/env` | config via `Config.pp` — `[@secret]` values masked |
| `/routes` | all `spec` in JSON — the same as `kre routes` |
| `/beans`, `/beans.mmd` | the `[%wire]` graph: providers and controllers with their dependencies (JSON, mermaid); `Actuator.make ~beans:app.beans` |
| `/metrics` | Prometheus text format: latency per route, status codes, `Gc.quick_stat` |
| `/openapi.json` | the same as `--emit-openapi` |

Protected with `[@@@guards]` like any controller; by default — loopback only.

### Profiles

`Kre.Config.profile ()` reads `config/default.env`, then `config/${KRE_ENV}.env` (default `dev`), then the real environment; later sources take precedence. Usage: `Config.load_exn ~env:(Kre.Config.profile ()) ()`. A provider for one environment — `[@@@profile "dev"]`: `[%wire]` builds `let module X = (val (match Kre.Wiring.profile () with "dev" -> (module Dev.Make () : I.S) | _ -> (module X.Make () : I.S)))`, so only the selected one is built. A provider without a profile is required; group members have no hooks, `[@@on_event]`, `[@@job]`, `[@@health]` or schedules — only `I.S` is visible from outside.

## Live data, scripts and jobs

Live data without manual subscriptions, web developer tools, and DB-backed jobs. Four ideas; live data is checked at compile time instead of tracked at runtime.

| Feature | Kre | Phase |
| --- | --- | --- |
| Auto refresh (the page refreshes when the tables it read change) | Live loaders: a route's table dependencies are known **statically** from sqlgg | 2 |
| Scripts (one-off scripts with the application context) | `[@@command]` (phase 3, `docs/commands.md`) instead of `kre generate script` + `kre run NAME` | 3 |
| Jobs as tables (`CREATE TABLE … job`) | `Kre.Job` (phase 3): one `kre_jobs` table and typed queues instead of a table per job type | ✅ |
| Developer UI: schema designer, data browser, logs | `kre dev` — a web UI on top of Actuator | 3 |
| `schema.sql` as the source of truth, types from it | we **do not take** the direction, we take the import: `kre import-schema` for brownfield | 1 |

### Live loaders — auto refresh via static analysis

There is no need to track the tables read during rendering at runtime and listen to Postgres `LISTEN/NOTIFY`: both halves are known at compile time, because sqlgg parses SQL:

1. sqlgg knows which tables each query **reads** and which it **writes** (`INSERT/UPDATE/DELETE`). Kre extends the generated code with per-function metadata `reads : string list`, `writes : string list`.
2. A handler that calls service functions does not know their tables statically (that is beyond ppx). So dependencies are declared on the handler: `[@@live ["cats"; "users"]]`, and an e2e test checks that the declared set ⊇ the set actually read (the runtime counts the `reads` of the called sqlgg functions in `KRE_ENV=test` mode). A mismatch is a test failure, not a silent loss of updates.
3. After a transaction commits (or after any writing sqlgg function outside a transaction) `Kre.Live.publish` broadcasts `Table_changed t` — without DB triggers, so it also works on MariaDB/TiDB, which have no `NOTIFY`. For Postgres, `LISTEN/NOTIFY` is optional, to catch external writes.
4. `spec.route.live : string list` goes into the generated client: `Cats_client.find_all` gets `~subscribe:true`, and `Router.child ~live:true` reruns the loader on an event from the SSE channel `/__kre/live`. For multi-process — pub/sub via Redis or Postgres; for one process — in-memory.

Result: `Cats.index` on the frontend updates when someone adds a cat, without a single line of subscription code in the application — and with a checkable dependency list.

### Scripts

`kre generate script backfill_ages` creates `scripts/backfill_ages.ml` with the stub `let main (module Db : Db.S) (config : Config.t) = …`; `kre run backfill_ages` builds and runs it with the same `Config.load` and pool as the server. This covers one-off tasks and "if only I could quickly run one data migration".

### Jobs as tables

Done in phase 3 differently from what follows: one `kre_jobs` table with a JSON payload and `'a Kre.Job.queue` queues (name + dto). A table per job type would need a migration and generated code for each queue, while dto checks the payload type anyway. See `docs/jobs.md`. The original sketch:

```ocaml
type t = { id : int [@primary] [@auto]; cat_id : int; email : string }
[@@deriving table ~name:"send_welcome_jobs" ~job]
```

`~job` adds the columns `status`, `attempts`, `run_at`, `last_error`, `locked_by` and generates `enqueue : t -> unit Lwt.t` and `Worker.run ~handler:(t -> (unit, string) result Lwt.t) ~concurrency ~retry`. The queue is the table itself with `SELECT … FOR UPDATE SKIP LOCKED`; no Redis for the basic case. This is the default implementation of the Queues chapter (phase 3); a Redis-backed queue — only if needed.

### kre dev

A web UI on the same port under `/__kre/`: the route list (`spec`), table schema and data (from `Kre.Table.Registry` + sqlgg queries, row editing), real-time request logs (SSE), live subscription status, OpenAPI. There is no schema designer: the schema is OCaml code and needs no editor. Enabled only with `KRE_ENV=dev`.

### Direction of truth: the type, not SQL

The source of truth is not `schema.sql` with types generated from it. We keep OCaml records (where opaque types and `dto` live) and generate `schema.sql`. For brownfield (an existing MariaDB/TiDB) — `kre import-schema --url … --out shared/gen/`: sqlgg parses `SHOW CREATE TABLE` and writes records with `[@@deriving table, dto]`, which are then edited by hand and become the source. A one-off import, not two-way sync.

## Phase 3 features

The rule is the same: only functions, modules, functors and ppx; no classes, reflection or runtime registries. If a feature is usually built on runtime magic (model callbacks, lazy-loading proxies, aspect-oriented interception), we take the result and replace the mechanism with a build-time check. What already exists (controllers, DI, guards, interceptors, dto, config, events, cron, cache, SSE/WS, JWT, Actuator, live loaders, table + sqlgg, migrations, typed client and router, `[@@transactional]`, `[@@authorize]`) is not included here.

| # | Kre | Wave |
| --- | --- | --- |
| 1 | `Kre.Table.crud` prints `by_<col>` for `[@unique]` (one row), `[@index]` and `[@references]` (a list), and `count`; sqlgg types them | ✅ |
| 2 | `[@@etag]` on GET: ETag from the body, `If-None-Match` → 304 | ✅ |
| 3 | `[@@retry n]` `[@@backoff s]` on any function → `Kre.Retry.run`; retry on exception. Not an interceptor: it is an attribute on a service function | ✅ |
| 4 | `[%wire]` exposes the graph (`Wiring.beans`); `/actuator/beans` (JSON) and `/actuator/beans.mmd` (mermaid) | ✅ |
| 5 | `kre-client.testing`: the generated typed client calls the application handler without a socket (`Kre_testing.use`) | ✅ |
| 6 | the whole query string into a record with `[@@deriving search, dto]`: `~(search : (Cat_search.t[@search]))`. The codec moved to `Kre_shared.Search` (native and Melange): one `Cat_search.codec` for the server (`Kre.Extract.search`), the page router and the client (`Spec.Search`, `Wire.search`) | ✅ |
| 7 | `Kre_shared.Page`: `Request.t` is a ready-made search record (`?page&size`, page ≥ 1, size 1–100) for `[@search]`; `'a t` with `total`; `-- @page` (`LIMIT/OFFSET`) in `Table.crud`; return `Cat.t Kre_shared.Page.t`, the client gets the same type | ✅ |
| 8 | `[@@command "…"]` on a function with module parameters in a separate file: `[%wire]` collects `app.commands`, `App.run ~commands` runs `main.exe seed --count 3` between `on_start` and `on_shutdown`; options come from labels, parsing — `Kre_shared.Scalar` (no cmdliner: the same modules as for query) | ✅ |
| 9 | `Kre.Job`: typed queues (`'a queue` = name + dto), one `kre_jobs` table (`Kre.Job.table`), `FOR UPDATE SKIP LOCKED`, retries with a doubling delay, `dead` after `attempts`; `[@@job q]` in a provider, the worker is the hooks of the `Kre.Job.S` provider, started by `[%wire]`. `enqueue` goes through `Db` and joins the open transaction | ✅ |
| 10 | `Kre_shared.Time` (RFC 3339, native and Melange, `DOUBLE` seconds in the database), `[@created_at]`, `[@updated_at]`, `[@version]` in `table`; `update` with `WHERE version = …`, 0 rows → 409 | ✅ |
| 11 | entity parameter: `~(cat : (Cat.t[@load Cats.find]))` with the `:cat` segment — the segment is parsed by `Cat.Id` (type `M.t` → `M.Id`: ppx does not see the loader's type), `Kre.Route.load` → 404; `[@@authorize]` receives the loaded record | ✅ |
| 12 | `kre generate controller dogs name:string age:int born:time good:bool` (phase 1 templates + fields): a type with `[@@deriving table, dto]`, DTO, in-memory service, controller, test with sample values; the project builds and passes the test (`test/scaffold/new.t`). SQL and `.mlx` pages are not generated: the sqlgg rule lives in the project's dune, and pages depend on the application's router | ✅ |
| 13 | `[@@deriving workflow]` + `[@@transitions { pay = (function Cart -> Paid); … }]`: transitions are a `function` over constructors (a typo is a compile error), `transition`, `next`, `apply` (`` `Not_allowed ``), `allowed`, `sources`, `workflow_mermaid`; native and Melange (`docs/workflow.md`) | ✅ |
| 14 | `Kre.Profiler`: a middleware collects per request the SQL (drivers and `Db.query` call `Profiler.sql`), time, status; `/__kre/profiler` (HTML) and `.json`, N+1 flag (≥ 3 identical queries); `KRE_ENV=dev` only | ✅ |
| 15 | `Kre.Mail`: `t` (recipient required, `Refined.Email.t`), `render` (RFC 5322, multipart, subject encoding), providers `Smtp (Config)` (no TLS) and `Outbox ()` with a preview at `/__kre/mail`. Mail is not in `.mlx`: there is no server-side reason-react rendering in native | ✅ |
| 16 | `[%http_client: val … [@@get "/users/:login"]]` — a signature of calls → a functor `(Config : sig val url : string val headers : … end)` on top of `Kre_client.Http`/`Wire` (`Http.request ?base`); native and Melange (`docs/http-client.md`) | ✅ |
| 17 | Static asset links checked at build time: `[%asset "logo.png"]` → `Kre_shared.Asset.t` with the address `/assets/logo.<hash>.png` (missing file — build error with a hint of a similar name); `[%icon "cat"]` → `Kre_shared.Icon.t`, SVG from `assets/icons/cat.svg`, embedded at build time; `Kre.Assets.middleware ~dir` serves files with a permanent cache; `Kre_client.Icon.view` renders the icon | ✅ |

The `assets/` folder lives at the application root (the parent of the file's directory, as for `[%wire]`); in dune it must be listed in `(preprocessor_deps (source_tree ../assets))` so that a file change rebuilds the links. The hash is the first 8 characters of the MD5 of the contents: the address changes with the file, so the cache can be permanent. `Kre.Assets.middleware` serves `/assets/<name>.<hash>.<extension>` from the directory and checks that the hash matches the current file (otherwise 404, not an old file under a new name).

What we do not do: model callbacks and ORM lifecycle events (hidden side effects — for us that is a service function or `Events`), install recipes and runtime autoconfiguration (we have `[%wire]` at build time), mixins and plugin bundles (these are modules and dune libraries), HATEOAS.

### Wave 4 features

| # | What | Kre | Status |
| --- | --- | --- | --- |
| 18 | role check | `[@@role g]` — a guard of any type; the handler does not need the value | ✅ |
| 19 | validation against the database (unique values) | `[@@check f]` — a check over the parsed arguments, `Error` → 422 with field paths; `Kre.Route.validated`; runs after `[@@authorize]` | ✅ |
| 20 | signed URLs | `[@@signed secret]` + `Kre.Signed.url` — `expires` and HMAC-SHA256 as the last parameter, otherwise 403; `Kre.Signed.guard` | ✅ |
| 21 | slugs | `[@slug_from name]` in `table`: `for_insert`/`for_update` fill the field with `Kre_shared.Slug.of_string` of the source column's value; a missing field is a build error | ✅ |
| 22 | ULID keys | `Kre_shared.Ulid.Make ()` (format check, native and Melange) + `Kre.Ulid.next ()` (48 bits of time, 80 random), `[@ulid]` in `table` — `VARCHAR(26)`, no auto-increment, the id is inserted | ✅ |
| 23 | pruning old rows | `[@prune]` on a time field: `-- @prune` in `Table.crud` (`DELETE … WHERE field < @before`); run it with `[@@interval]` in a provider | ✅ |
| 24 | scopes | `[@@scopes [ ("available", "status = 'available'") ]]` → `all_<scope>`, `page_<scope>`, `count_<scope>` in `Table.crud`; sqlgg checks the conditions | ✅ |
| 25 | API filters | `[@filter Exact | Partial | Range]` → `-- @filter`/`@filter_count` with sqlgg `{ … }?` conditions (`None` — the condition is dropped); on the client — a search record (`examples/shelter/shared/cat_filter.ml`) | ✅ |
| 26 | relations and eager loading | `[@references M]` → `by_<fk>_any` (`IN @<fk>_list`) in `Table.crud`, `Kre.Table.group ~key` — children of many parents in one query (`Cats.owned_by`) | ✅ |
| 27 | embedded records | `[@embedded]` — a record from the same `type … and …` is stored as `<field>_<subfield>` columns; the table is the record that nobody embeds; `of_row` assembles the nested record; nesting of any depth | ✅ |
| 28 | serializer groups | `[@groups ["admin"]]` in `dto` → `to_json_<group>` and `t_jsonschema_<group>`; outside the group the field is hidden (`writeOnly`), the field must be an `option` (`[@option]` is added); the handler picks the representation: `(Member.t [@view "admin"]) Lwt.t` | ✅ |
| 29 | provider decorators | `[@@@decorates I.S]` — a wrapper provider; consumers get the wrapper, the wrapper gets the original; several wrappers form a chain in file order; `Make` must take `I.S` | ✅ |
| 30 | all providers of an interface | parameter `(All : Kre.Wiring.ALL with type t = (module I.S))` — `[%wire]` passes all `I.S` providers except the provider itself and the wrappers | ✅ |
| 31 | per-environment providers | `[@@@profile "dev"]` — the provider is chosen at startup by `KRE_ENV` (`Kre.Wiring.profile`); a provider without a profile is required; hooks in a group are a build error | ✅ |
| 32 | locks | `[@@lock "name"]` + `Kre.Lock.Make (Db)` (table `kre_locks`: insert or take over an expired row, owner check, release in `finalize`, TTL 600 s) — the function never runs on two servers at once; a held lock means skip | ✅ |
| 33 | API tokens with abilities | `Kre.Token.Make (Db)` (table `kre_tokens`: ULID, owner, SHA-256 of the token, space-separated abilities; `*` — everything) + `[@@ability "cats:write"]` — guard `Tokens.ability`, the dependency `Tokens : Kre.Token.S` is added to `register` and to `[%wire]`; 401 without a token, 403 without the ability | ✅ |
| 34 | queue dashboard | `Jobs.dashboard` — `/__kre/jobs` (HTML), `/__kre/jobs.json`, `POST …/:id/retry` and `…/:id/delete`; loopback only; `[%wire]` adds it to `app.controllers` by itself | ✅ |
| 35 | precognition | the header `Precognition: true` on POST/PUT/PATCH/DELETE — parsing, guards, `[@@authorize]` and `[@@check]` without calling the handler: 204 `Precognition-Success: true` or the same error (`Kre.Route.precognition`) | ✅ |
| 36 | a resource from one declaration | `[%%resource { service = (module Books : Books.S); entity = Book; actions = [ Index Book_filter; Show; Create Book_draft; Remove ] }]` — before the controller pass it expands into ordinary handlers (`[@search]`, `[@load Books.find]`, 201, 204), the service must have `page`/`find`/`create`/`remove`; `[%wire]` expands it too | ✅ |

## Phases and acceptance criteria

A phase is closed when its criterion passes in CI. Order within a phase is top to bottom; each row is a separate task for Claude Code with its own PR.

### Phase 0 — foundation and decisions (1 week) — done

| Task | Criterion |
| --- | --- |
| Repository, dune-project, 4 opam packages, CI (build + test on 5.5) | `dune build @all` green on empty packages |
| Check Melange under 5.5; fix the version rule for `shared/` | decision recorded in the "Stack" section |
| Evaluate typegist (codec benchmark, Melange build, opam status) | decision (a)/(b) recorded in the dto section |
| Inspect jsonkit: what it has of `of_json/to_json`; decide where the codecs live | decision recorded in the dto section |
| `Kre.Error`, `Response`, `Codec`, `Validation`, `Refined`, `Spec`, `Controller`, `run`/`app` per the `.mli` from the Core section | alcotest for each module; `Kre.App.handler []` responds 404 via `Error.to_response` |

### Phase 1 — core, cats end-to-end (3–4 weeks)

| Task | Criterion |
| --- | --- |
| ✅ ppx `controller`: attributes, classification, `Paths`/`spec`/`register`, all errors | cram for the reference output and each error; the cats controller compiles and passes e2e via `Dream.test` |
| ✅ ppx `dto` (basic, `~strict`, `[@validate]`, opaque fields via `Json.S`) | cram for the output; e2e cats: 422 with the field path, `~strict` |
| ✅ `Kre_shared.Refined` (String, Int, Enum, Email, Make; Regex — open question) | schemas contain the constraints; `of_string` works in path/query |
| ✅ ppx `config` (+ `Kre.Config`, profiles) | `load` collects all errors at once; cram for the output and errors |
| ✅ `--emit-spec`, `--emit-openapi`; `kre client` (melange + native), `kre openapi`, `kre routes` | the cats OpenAPI passes `openapi-spec-validator`; the native client passes e2e on cats against a live server |
| ✅ `Kre_client`: `Http`, `Error`, `Wire`, `Promise` | `examples/cats/client_js`: the generated client, built by Melange, in node 22 against a live server (`NODE=` sets the binary) |
| ✅ `Kre_client.Router` + `[%path]`, `search`, `params` | node: `href`, matching, `search` with a default and an error, SSR `link` and `View`; cram: `link` with wrong params does not compile |
| ✅ `Kre.Db` (pool, transactions) + `Kre_db_mariadb` (sqlgg traits); `table`: `schema`, `schema.sql`, `of_row` | sqlgg queries against the generated `schema.sql` compile and run on MariaDB 11.8 (alias `@db`, a separate CI job) |
| ✅ `kre migrate up/down/status/new` (+ `Kre.Migration`) | e2e on MariaDB: empty database → up → down, programmatically and via the CLI |
| ✅ `kre new`, `kre generate controller/service/dto` | cram (`test/scaffold/new.t`) with installed packages: the project builds and passes its test; the resource from `generate controller` builds and passes a CRUD test; existing files are not overwritten |
| ✅ Docs: chapters Overview + Fundamentals + Validation/Serialization/Configuration + Data (+ OpenAPI/CLI, client) | 24 chapters in `docs/`; their code is files from `examples/cats` and `docs/examples`, mdx (`$MDX file=`) checks the text against the files, and `docs/examples/test` runs the chapter examples via `Dream.test` |

**Phase 1 criterion:** `examples/cats` — the running example — builds (`dune build @all`), `dune test` is green, `kre client` regenerates the client with no diff, the page `/cats/1` in the browser shows a cat from the DB.

**Status (phase 1 is closed, except the manual check in a browser).** `dune build @all` and `dune test` are green (`NODE=` for the Melange tests), `@db` is green on MariaDB 11.8; the client is generated by a dune rule from `spec.json`, so it cannot diverge from the controller. Web part: `examples/cats/web` builds the page into ES modules (React from esm.sh via an import map, no bundler), `bin/web.ml` serves `/static/**` and `page.html` on GET with `Accept: text/html`, everything else is the API. With `DATABASE_URL` the server uses `Cats_db_service` and applies migrations at startup; `curl` confirms HTML on `/cats/1` for the browser and JSON with a cat from the database for `fetch`. Opening the page in a browser by hand has not been checked yet:

```
SESSION_SECRET=dev DATABASE_URL=mariadb://user:pass@127.0.0.1/cats dune exec examples/cats/bin/main.exe
open http://localhost:8080/cats/1
```

### Phase 2 — a real application (4–6 weeks)

`[@@sse]` and `[@@@gateway]`/`[@@subscribe]` for websockets with types from shared; `[@@cron]`; `Events` (typed bus); `[@@cache]`; `table` CRUD; `dto` mapped types (`~partial_of`, `~pick_of`); auth strategies (session, JWT) + `Auth.role`; secure headers/CORS/rate-limit middleware; `[@@@version]`; docstrings → OpenAPI; `Kre_db_pgx`. Criterion: the Security, HTTP, WebSockets, Events, Task scheduling, Caching chapters are closed.

**Phase 2 status** (updated as work goes):
- ✅ `[@@header]`, `[@@redirect]`, `[@@timeout]`, `[@@@error_handler]`
- ✅ `[@@transactional]` + `[@from Db.tx]`, `[@@authorize]`; then implicit transactions: `with_conn`/`transaction` inside an open one join it, `[@@transactional]` needs only a `Kre.Db.S` dependency
- ✅ secure headers/CORS/rate-limit: `Kre.Secure_headers`, `Kre.Cors`, `Kre.Rate_limit` (`docs/security.md`)
- ✅ `[@@sse]`: the type `T.t Lwt_stream.t Lwt.t` and the attribute must go together; `Kre.Route.events` with an explicit module — a GADT constructor with `'a Lwt_stream.t` is impossible (the type is not injective); `kre client` skips such routes for now (subscription — `EventSource`)
- ✅ WebSocket: `Kre.Gateway` (`{event, data}` frames, `on`/`notify` with explicit body and response modules, `send`/`broadcast`, errors — an `error` event with Problem Details), ppx `[@@@gateway "chat"]` + `[@@subscribe "event"]`, `[%wire]` sees gateways; tested with a live WebSocket from node 22
- ✅ Actuator: `Kre.Actuator.make` (`/health`, `/info`, `/env`, `/routes`, `/openapi.json`, `/metrics`), `[@@health]` in providers, `Config.pairs` from the deriver (`docs/actuator.md`)
- ✅ cache: `[@@cache ttl]` (GET response by URL, `X-Cache`), `Kre.Cache.memoize` (`find`/`evict`/`clear`) (`docs/caching.md`)
- ✅ scheduling: `[@@cron]` (`Kre_shared.Cron` is parsed in ppx at build time, `next` without `Unix` — works in Melange too), `[@@interval]`, `[@@after]`; `Kre.Schedule`, start/stop via `Kre.Wiring` (`docs/task-scheduling.md`)
- ✅ events: `Kre.Events` (`'a topic` with `Type.Id`, the bus `Make ()` as a provider), `[@@on_event]` in a provider, the subscription is generated by `[%wire]` (`docs/events.md`, `examples/events`)
- ✅ serialization: `[@exclude]` (writeOnly), `[@transform f]`, mapped types `~partial_of`/`~pick_of`/`~omit_of` with functions `<x>_of_<t>` and `<x>_apply` (types from the same file)
- ✅ Controllers page: `[@@head]`, `[@@options]`, `[@@all]`, the `*` mask + `[@wildcard]`, HEAD via GET, `[@@@host]` + `[@host_param]`
- ✅ `Kre_shared.Id.Make ()`: typed entity identifiers (`Cat.Id.t`)
- ✅ interceptors: `Kre.Interceptor.t` (a polymorphic `around` over a typed result), `[@@intercept]`/`[@@@intercept]`, ready-made `logging`, `timeout`, `map_error`, `tap`, `chain`
- ✅ parameter attributes: `[@param]`, `[@query]`, `[@body]`, `[@header]`, `[@cookie]`, `[@signed_cookie]`, `[@session]`, `[@headers]`, `[@cookies]`, `[@ip]`, `[@host]`, `[@req]` (`Kre.Extract`), headers and cookies in spec/OpenAPI, headers in the client
- ✅ build-time DI: `[%wire]`, providers by module shape, `[@@@primary]`, selection by parameter name, hooks, build errors (see "Wiring")
- ✅ table CRUD: `Kre.Table.crud` → `crud.sql` → sqlgg `Cats_crud` (`all`/`insert`/`find`/`update`/`delete`), `for_insert`/`for_update` (`docs/data.md`)
- ✅ live loaders: `Kre.Live` (in-memory bus, `publish`/`subscribe`, channel `/__kre/live`), the driver reports SQL (`read`/`wrote`), `Db.transaction` holds changes until commit, `[@@live]` → `spec.live` + `x-kre-live` + `Cats_client.Live`, `Router.child ~live`, list check with `KRE_ENV=test` (`docs/live.md`). sqlgg does not provide `reads`/`writes` metadata — tables are taken from the SQL text in the traits
- ✅ PostgreSQL: `kre-db-postgresql` (libpq, not pgx — see "Kre.Db"), `Kre.Table.schema` with a dialect, `examples/cats/postgresql` + a CI job with postgres:17
- ✅ `examples/shelter` — the phase 2 acceptance criterion: everything together on MariaDB + node (see "A whole application"); `[@@deriving dto]` on a variant without arguments gives a scalar
- ✅ auth: `Kre.Jwt` (HS256, `sign`/`verify`/`bearer`, errors `` `Jwt of Malformed | Bad_signature | Expired ``), `Kre.Guard.session/map/check/optional`; roles — `Guard.check` into an evidence type (`docs/authentication.md`)

### Phase 3 — ecosystem

The tables "Phase 3 features" and "Wave 4 features", by wave. `kre migrate diff`; queues; GraphQL code-first; resilience/idempotency/outbox; i18n; file storage; microservice transports. Prioritized by the first real project on Kre.

### Map of docs chapters

| Section | Status in Kre |
| --- | --- |
| Overview (10 chapters) | phase 1; Custom decorators = `[@from]` |
| Fundamentals | phase 1; Circular dependency, Module reference, Discovery, Lazy-loading, Platform agnosticism — one page "not needed and why" |
| Application | Configuration/Validation/Serialization/Logging — phase 1; Events/Task scheduling — 2; Queues/i18n/Mail/File storage — 3 |
| Data | one chapter (sqlgg + table + migrations) — phase 1; Caching — 2; MongoDB — no |
| Security | phase 2 |
| HTTP | Cookies/Session/Upload/Compression/MVC — phase 1 (Dream); Versioning/SSE/Webhooks — 2 |
| Observability | OpenTelemetry via ocaml-opentelemetry — phase 2; the rest — no |
| Reliability | Health checks — 2; the rest — 3 |
| GraphQL, Microservices | phase 3 |
| WebSockets | phase 2 |
| Standalone apps, CLI, OpenAPI | phase 1 |
| Recipes | REPL = utop, Hot reload = dune -w, Serve static = Dream.static, CLI commands = cmdliner, CRUD generator = `kre generate`; CQRS — 3 |

## Development conventions and open questions

These rules are for the repository's `CLAUDE.md`; they override any defaults.

### Code

- OCaml 5.5, `(lang dune 3.23)`, ocamlformat 0.29 with the `default` profile; CI fails on unformatted code.
- Minimal code, no functions for a single call. Illegal states unrepresentable: `option`/`result`/variants instead of flags and checks. No `assert false`, `failwith` in library code, `Obj.magic`.
- Every public module has an `.mli`; `Kre.*` — exactly the signatures from the Core section; a signature change means editing this document in the same PR.
- Generated ppx code contains only calls to `Kre.Route`/`Kre_shared.Json`/`Kre_shared.Scalar`, no logic; logic lives in the runtime, where it can be tested without ppx.
- Modular explicits — only in `server/` and `bin/`; `shared/` and `client/` — syntax that Melange builds.
- Dream is not wrapped: `Dream.request`, `Dream.middleware`, `Dream.response` in Kre's public signatures are allowed and preferred.

### ppx

- One driver `kre.ppx` (`ppxlib` ≥ 0.38); transformations are registered one by one, each in its own file with its own set of expect tests.
- All errors — `Location.raise_errorf` with the location on the offending node and text of the form "what is wrong → what to do": `handler find_one: missing return type annotation; add : Cat.t Lwt.t`.
- No warnings instead of errors; no default "guessing" when an annotation is missing.
- Generated names have the `__kre_` prefix; user names are not shadowed.

### Tests and docs

- For each transformation: an expect test of the reference output + one test per error.
- `examples/cats` is always green; it is the integration test of the core.
- Chapters in `docs/` follow the "Map of docs chapters"; each contains a working example. Code in a chapter is not text but a `<!-- $MDX file=… -->` reference to a file that builds (`examples/` or `docs/examples/`); `dune test` fails if the text diverges from the file, `dune promote` updates the chapter. `sh` blocks are marked `<!-- $MDX skip -->`. A chapter without such a block does not count as written.

### Process for Claude Code

- One phase table row = one PR with tests. Start with phase 0, in order; phase 1 — with ppx `controller`.
- Before implementing a section, reread it in this document; if the design does not match reality (library version, impossible in ppx), first edit the document with a justification, then the code.
- Do not widen a phase's scope: an idea that is not in the table goes into "Open questions".

### Open questions

- [x] Melange under OCaml 5.5: `melange.7.0.1-55` exists; one switch, 5.5 syntax allowed everywhere (phase 0).
- [x] typegist: option (b), not used (phase 0, dto section).
- [x] jsonkit: `of_json`/`to_json`/`t_jsonschema` exist on both backends; `Json.S` mirrors their shape (phase 0, dto section).
- [ ] jsonkit: a decoding mode that accumulates errors with paths (`["age"]`) — needed for applicative 422s; until then — the first error, without a path.
- [ ] Regular expressions in `Kre_shared` (`Validation.regex`, `Refined.Regex`): `Str` exists only in native; options — `re` (check that it builds in melange) or a custom implementation on `Js.Re` behind a shared interface.
- [x] String length in `Validation.min_length`/`max_length` counts Unicode code points on both ends, like JSON Schema `minLength`: `kre.text` / `kre-client.text` (`Kre_text.length`) is one `.mli` with a native implementation (UTF-8 lead bytes) and a Melange one (`Array.from`); `test/text` checks the same strings natively and in node.
- [x] sqlgg: traits come from `sqlgg.mariadb` (opam `sqlgg.20260721`), `Kre.Db` — pool and transactions; `schema.sql` is printed by a binary with the table list, no registry needed. The `jongleb/sqlgg` fork is not required yet; if its features are needed (IR, lattice-nullability) — a pin in `dune-project`.
- [ ] Name: `Kre` is a working name; check for collisions in opam before publishing.
- [x] `.mlx` vs reason syntax for JSX: `.mlx` (a dune dialect, phase 2).
- [x] Dream: `1.0.0` is out, dependency `dream >= 1.0.0`.
- [ ] WebSocket: on a close from the client side the server receives `None` and calls `Dream.close_websocket`, but the client (node 22) gets no close acknowledgement within 3 s. Messages flow. Check with the Dream 1.0 `k-websocket` example and, if it happens there too, — in Dream.
- [ ] `--emit-spec` runs the composition root (`main.ml`), and it loads the config first, so the build needs environment variables (in cats the dune rule sets `SESSION_SECRET=unused`). `spec` is static; an option — `kre` itself builds a small binary that prints `Cats_controller.spec`, without running `main`.
- [ ] `ssl 0.8.0` built against OpenSSL 4 fails during `conduit-lwt-unix` initialization (minimum SSL3 is no longer supported), and the native client on cohttp fails with it. The local switch is rebuilt against `openssl@3` (`PKG_CONFIG_PATH=$(brew --prefix openssl@3)/lib/pkgconfig opam reinstall ssl`); ubuntu in CI has OpenSSL 3. Fix it in ssl or move the native client off conduit.
- [x] Controller attributes postponed from phase 1: done in phase 2, except `[@@sse]` (its own row); `[@@@inject]` and `[@codec e]` are not needed (see the ppx: controller section).

# What Kre has and what is in progress

✅ done and covered by tests · 🔜 next (phase 2) · ⏳ later (phase 3) · — not needed in OCaml

The whole application (users, cats, adoptions; everything from the tables below together) is `examples/shelter`.

Everything below is modules, functors, functions and ppx attributes; there are no classes, no reflection and no runtime container. DI and routing errors are compile errors.

## Application and DI

| Kre | Status | Example |
| --- | --- | --- |
| `[%wire]` scans the application directory at build time and assembles the application | ✅ | `examples/cats/bin/main.ml` |
| a module with `Make` or `module type S` is a provider by itself | ✅ | `examples/cats/server/cats_service.ml` |
| dependency injection through functor parameters `Make (Db : Kre.Db.S)` | ✅ | `examples/cats/db/cats_db_service.ml` |
| choosing an implementation: `[@@@primary]`; functor parameter name = provider name | ✅ | `test/wire/wire.t` |
| lifecycle hooks: `let on_start` / `let on_shutdown` in the provider | ✅ | `examples/cats/db/database.ml` |
| transient instances: `Make ()` gives a new instance per application | ✅ | `Cats_service.Make ()` |
| request-scoped values: `Dream.field` + `[@guard]` | ✅ | `docs/examples/request_id.ml` |
| configurable providers: a functor with a config module | ✅ | `Kre.Db.Make (Driver) (Config)` |
| typed configuration: `[@@deriving config]` | ✅ | `examples/cats/server/config.ml` |
| profiles: `Kre.Config.profile ()` (`config/$KRE_ENV.env`) | ✅ | `docs/configuration.md` |
| `[@@@fallback]`: a fallback provider used when there is no other | ✅ | |
| lazy and conditional providers | ⏳ | |
| `Kre.Mail`: `Smtp`, `Outbox` with a preview at `/__kre/mail` | ✅ | `docs/mail.md` |
| `Kre.Job` + `[@@job q]`: a queue in the same DB, `SKIP LOCKED`, retries, enqueue inside a transaction | ✅ | `docs/jobs.md` |
| `[@@command "…"]` + `app.commands` → `main.exe seed --count 3` | ✅ | `docs/commands.md` |
| `Kre.Profiler`: requests with their SQL and an N+1 marker, `/__kre/profiler`, dev only | ✅ | `docs/profiler.md` |
| `[%asset "logo.svg"]`, `[%icon "cat"]`: the file is checked at build time, hashed URL, `Kre.Assets.middleware` | ✅ | `examples/shelter/client/pages.mlx` |
| the dependency graph: `app.beans` from `[%wire]` → `/actuator/beans`, `/actuator/beans.mmd` | ✅ | `docs/actuator.md` |
| circular dependencies, looking up providers at runtime: compile error / not needed | — | `docs/not-needed.md` |

## Controllers

| Kre | Status |
| --- | --- |
| `[@@@controller "cats"]` | ✅ |
| `[@@get ":id"]`, `[@@post]`, `[@@put]`, `[@@patch]`, `[@@delete]` | ✅ |
| `[@@head]` `[@@options]` `[@@all]`; HEAD → GET without a body | ✅ |
| `[@@get "*"]` + `[@wildcard]`; exact routes win over the wildcard | ✅ |
| `[@@@host ":account.example.com"]`, `[@host_param "account"]` | ✅ |
| `[@@status 201]` | ✅ |
| `[@@header (k, v)]` | ✅ |
| `[@@redirect "/x"]`; dynamic: return `Dream.redirect` | ✅ |
| server-sent events: `T.t Lwt_stream.t Lwt.t` + `[@@sse]` | ✅ |
| `[@@@version 2]` (on the controller) | ✅ |
| `[@@version 2]` on the handler | ✅ |
| server-rendered views | ⏳ |

## Parameters

| Kre | Status |
| --- | --- |
| `~(id : Cat.Id.t)` with `:id`; `[@param "id"]` | ✅ |
| `~(page : int)`, `?(limit : int = 20)`, `[@query "page-size"]`, `[@query]` | ✅ |
| `~(cat : (Cat.t[@load Cats.find]))`: id from the path → record or 404 | ✅ |
| `~(search : (Cat_search.t[@search]))`: one record on the server, in the client and in the page URL | ✅ |
| `~(body : T.t)`, `[@body]`, `[@body "name"]` | ✅ |
| `[@header "X-Client-Name"]`, `[@headers]` | ✅ |
| `[@cookie "x"]`, `[@signed_cookie "x"]`, `[@cookies]` | ✅ |
| `[@session "user_id"]` | ✅ |
| `[@ip]`, `(req : Dream.request)`, `[@req]` | ✅ |
| custom parameters: `[@from guard]` | ✅ |
| `[@file "avatar"] : Kre.Upload.t`, `[@files "photos"]`, `[@form "title"]` (the type decides the parsing) | ✅ |
| writing to the response object: not needed, the response is the return value | — |

## Request pipeline

| Kre | Status |
| --- | --- |
| middleware: `Dream.middleware`; `[@@@use]`, `[@@use]` | ✅ |
| guards: `[@@guards]`, `[@guard g]`, roles: `Guard.check` into an evidence type | ✅ |
| `[@@authorize fun ~user ~id -> …]` | ✅ |
| interceptors: `[@@intercept]`: `logging`, `timeout`, `map_error`, `tap` | ✅ |
| parameter parsing: the parameter type (`Kre_shared.Scalar`, `Refined`, `Id`) | ✅ |
| `[@@deriving dto]`: parsing = validation, 422 with paths | ✅ |
| exception filters: `error_handler`, `[@@@error_handler]`, Problem Details (RFC 9457) | ✅ |
| `[@@error_handler h]` on the handler (wins over the controller and global ones) | ✅ |
| `[@@transactional]`; `Db.with_conn` inside joins the transaction | ✅ |
| rate limiting: `Kre.Rate_limit` | ✅ |
| secure headers and CORS: `Kre.Secure_headers`, `Kre.Cors` | ✅ |
| authentication: `Kre.Jwt.bearer`, `Guard.session` | ✅ |
| `[@@etag]`, `Kre.Etag.middleware` → 304 | ✅ |
| `[@@retry 3] [@@backoff 0.1]` on any function | ✅ |
| `[%http_client: val user : login:string -> User.t [@@get "/users/:login"]]` → a functor over the base URL | ✅ |
| testing: `Kre_testing.use` + the generated client, no socket | ✅ |

## Data and serialization

| Kre | Status |
| --- | --- |
| validation: `Refined`, `[@validate]`, `~strict` | ✅ |
| `Kre_shared.Id.Make ()`: a distinct id type per entity | ✅ |
| `[@@deriving workflow]` + `[@@transitions { pay = (function Cart -> Paid) }]`: `apply`, `allowed`, `sources`, mermaid | ✅ |
| a variant without arguments + `[@@deriving dto]`: a string in JSON, paths, query and the column | ✅ |
| `[@@deriving table]` → DDL, `of_row` | ✅ |
| `[@created_at]`, `[@updated_at]`, `[@version]` in `table` + `Kre_shared.Time`; stale version → 409 | ✅ |
| `Kre_shared.Page`: `Request.t` via `[@search]`, `'a t` with `total`, `page` and `count` in `Table.crud` | ✅ |
| `Table.crud` → `by_<col>` for `[@unique]`/`[@index]`/`[@references]`, `count` | ✅ |
| sqlgg: SQL is checked against the schema at build time | ✅ |
| migrations: `kre migrate up/down/status/new` | ✅ |
| `[@exclude]` (writeOnly), `[@key]`, `[@transform f]`; groups are `~pick_of` projections | ✅ |
| `[@@deriving dto ~partial_of / ~pick_of / ~omit_of]` + `summary_of_t`, `update_apply` | ✅ |
| `Kre.Table.crud` → sqlgg module `all`/`insert`/`find`/`update`/`delete`; `for_insert`/`for_update` from `[@@deriving table]` | ✅ |
| `kre-db-postgresql` (libpq): sqlgg `-dialect postgresql`, `Table.schema Postgresql`, `insert_id` via `lastval()` | ✅ |

## Everything else

| Kre | Status |
| --- | --- |
| `--emit-openapi`, `kre openapi` (3.1, validated); `[@@summary]`, `[@@description]` | ✅ |
| typed client `kre client` (Melange + native) | ✅ |
| typed page router, `[%path]`, `params`, `search` | ✅ |
| `kre new`, `kre generate controller dogs name:string age:int born:time` | ✅ |
| `Kre.Events` (a topic typed by its event), `[@@on_event]`, subscription via `[%wire]` | ✅ |
| `[@@cron]` (checked at build time), `[@@interval]`, `[@@after]` | ✅ |
| `[@@cache ttl]` on GET; `Kre.Cache.memoize` → `{ find; evict; clear }` | ✅ |
| `Kre.Actuator`: health (`[@@health]` via `[%wire]`), info, env (secrets hidden), routes, openapi, Prometheus metrics | ✅ |
| `[@@@gateway "chat"]`, `[@@subscribe "say"]`, `~(body : T.t)`, `(socket : Kre.Gateway.socket)`, `broadcast` | ✅ |
| live loaders: `[@@live ["cats"]]`, publishing from the driver after commit, `/__kre/live`, `Router.child ~live`, list check with `KRE_ENV=test` | ✅ |
| microservices, GraphQL | ⏳ |

The whole application on one screen is `examples/showcase`: a server with all the example controllers; its route table is `examples/showcase/routes.t`.

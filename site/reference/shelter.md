<script setup>
const stats = [
  { value: "3", label: "controllers", note: "auth, cats, adoptions: 10 routes" },
  { value: "5", label: "tables", note: "4 from records, plus kre_jobs" },
  { value: "8", label: "providers", note: "wired by one [%wire]" },
  { value: "14", label: "tests", note: "13 against the handler, 1 in node" }
]

const authFlow = [
  { title: "Sign up", sub: "Login_dto parsed; users and credentials rows in one transaction", tone: "sky" },
  { title: "Log in", sub: "Credential.verify returns a User.Id.t, or nothing", tone: "mint" },
  { title: "Token", sub: "Kre.Jwt.sign puts the whole User.t into the claims", tone: "amber" },
  { title: "Auth.current", sub: "Parses the claim back into User.t, no database call", tone: "ember" },
  { title: "Auth.admin", sub: "Turns an Admin role into Auth.Admin.t evidence", tone: "magma" }
]

const jobFlow = [
  { title: "Enqueue", sub: "Jobs.enqueue Queues.congratulate inside the adoption transaction", tone: "ember" },
  { title: "Commit", sub: "The kre_jobs row exists only if the adoption does", tone: "amber" },
  { title: "Poll", sub: "The worker checks every 0.1 s with SKIP LOCKED", tone: "sky" },
  { title: "Run", sub: "Mailer.congratulate, marked [@@job Queues.congratulate]", tone: "mint" },
  { title: "Retry or done", sub: "Up to 3 attempts with doubling delays, then dead", tone: "violet" }
]

const clientFlow = [
  { title: "main.exe --emit-spec", sub: "The server describes its routes", code: "bin/spec.json", tone: "ember" },
  { title: "kre client", sub: "One typed module per controller", code: "cats_client.ml", tone: "amber" },
  { title: "routes.mlx", sub: "Typed routes with loaders and live tables", tone: "mint" },
  { title: "pages.mlx", sub: "React components over shared types", tone: "sky" }
]

</script>

# Shelter: a full app

<p class="lead">The shelter is a complete Kre application: members sign up, admins admit cats, members adopt them — at most two each — and staff get a letter for every new home. It uses auth, transactions, live pages, jobs, mail, commands, a typed frontend and a test suite that drives it from node. This page walks through every file.</p>

<StatGrid :stats="stats" />

All code below is imported from `examples/shelter` in the repository, so it is exactly what compiles and passes CI.

## The domain

Three records describe the shelter: users, cats and adoptions. A fourth table, `credentials`, belongs only to the server. The fifth, `kre_jobs`, is Kre's own job queue.

```mermaid
erDiagram
  users ||--o| credentials : "logs in with"
  users ||--o{ cats : "owns"
  users ||--o{ adoptions : "makes"
  cats ||--o| adoptions : "is adopted in"
  users {
    BIGINT id PK
    VARCHAR email UK
    VARCHAR role
  }
  cats {
    BIGINT id PK
    VARCHAR name
    BIGINT age
    VARCHAR status
    BIGINT owner_id FK
    BIGINT version
  }
  adoptions {
    BIGINT id PK
    BIGINT cat_id FK, UK
    BIGINT user_id FK
    DOUBLE adopted_at
  }
  credentials {
    BIGINT user_id PK, FK
    VARCHAR hash
  }
  kre_jobs {
    BIGINT id PK
    VARCHAR queue
    TEXT payload
    VARCHAR status
    BIGINT attempts
    DOUBLE run_at
    DOUBLE locked_until
    TEXT last_error
  }
```

`adoptions.cat_id` is unique, so a cat can find a home only once, even before any service code runs.

## The layout

```
examples/shelter/
  shared/      user.ml cat.ml adoption.ml session.ml
               login_dto.ml create_cat_dto.ml rename_dto.ml adopt_dto.ml
    melange/   the same files, compiled to JavaScript
  schema/      credential.ml (server-only table), schema.ml (prints DDL and CRUD SQL)
  server/      config.ml settings.ml database.ml inserted.ml
               auth.ml users_service.ml cats_service.ml adoptions_service.ml
               jobs.ml queues.ml mail.ml mailer.ml tasks.ml
               auth_controller.ml cats_controller.ml adoptions_controller.ml
    sql/       queries.sql, plus generated *_crud.ml checked by sqlgg
  bin/         main.ml: let app = [%wire]
  client/      routes.mlx pages.mlx scenario.mlx (+ generated *_client.ml)
  test/        test_shelter.ml run_scenario.ml
```

<Layers />

## Shared types

Everything that crosses the wire lives in `shared/`. Each record is compiled twice — natively for the server and with Melange for the browser — so the server and the pages agree on every field by construction.

A user has a typed id, a parsed email and a role. The role is a variant, so it is a string in JSON and in its column, and a `match` on it is checked for exhaustiveness.

<<< @/../examples/shelter/shared/user.ml

A cat brings refined name and age types, a status, an optional owner and a `[@version]` column for optimistic locking.

<<< @/../examples/shelter/shared/cat.ml

An adoption ties the two together. `[@created_at]` fills `adopted_at`, stored as seconds and sent as RFC 3339.

<<< @/../examples/shelter/shared/adoption.ml

The request bodies are small strict DTOs. Unknown fields are rejected, and a password shorter than eight characters is a 422 with the rule name before your code runs.

<<< @/../examples/shelter/shared/login_dto.ml

<<< @/../examples/shelter/shared/rename_dto.ml

One record becomes the table, the JSON codec, the OpenAPI schema and the client type:

<TypeFanout />

## Credentials never reach shared types

The password hash is not a field of `User.t`. It lives in its own table, in the `schema/` library, which the Melange build never sees. The type sent to the browser cannot contain a hash at all.

<<< @/../examples/shelter/schema/credential.mli

The record is `private`: the only way to make one is `make`, which salts and hashes with PBKDF2-SHA256. `verify` compares in constant time with `Eqaf` and returns the user's id as evidence, not a `bool`:

<<< @/../examples/shelter/schema/credential.ml{20-27}

Logging in needs a join, so it is hand-written SQL that sqlgg checks against the schema the tables print:

<<< @/../examples/shelter/server/sql/queries.sql

## Auth: JWT and role evidence

The shelter logs in with a bearer token. The token carries the whole `User.t` in its claims, so checking it needs no database query.

<Flow :steps="authFlow" caption="From a password to proof of a role" />

The interface is the interesting part. `Auth.Admin.t` is abstract, and only the `admin` guard can produce one:

<<< @/../examples/shelter/server/auth.mli

<<< @/../examples/shelter/server/auth.ml

Signing up runs in a transaction: the user row and the credential row are written together. The account whose email matches `ADMIN_EMAIL` becomes an admin; everyone else is a member.

<<< @/../examples/shelter/server/users_service.ml

The controller is three short functions:

<<< @/../examples/shelter/server/auth_controller.ml

## Controllers

The cats controller shows most of what a handler can say in its signature: a live list, a paged catalog read from the query string, an entity loaded from the path, a guard that demands admin evidence, and an authorization rule over the loaded record.

<<< @/../examples/shelter/server/cats_controller.ml

| Route | Handler | What protects it |
| --- | --- | --- |
| `POST /auth/signup` | `Auth_controller.signup` | `Login_dto` parsing, unique email (409) |
| `POST /auth/login` | `Auth_controller.login` | password check (401) |
| `GET /auth/me` | `Auth_controller.me` | `Auth.current` (401) |
| `GET /cats` | `Cats_controller.available` | public, live on `cats` |
| `GET /cats/catalog` | `Cats_controller.catalog` | `?page&size` parsed (400) |
| `GET /cats/:cat` | `Cats_controller.find_one` | `[@load Cats.find]` (404) |
| `POST /cats` | `Cats_controller.create` | `Auth.admin` (403) |
| `PUT /cats/:cat` | `Cats_controller.rename` | `Auth.current`, `[@load]`, `[@@authorize]`, version (409) |
| `POST /adoptions` | `Adoptions_controller.adopt` | `Auth.current`, `[@@transactional]` |
| `GET /adoptions/mine` | `Adoptions_controller.mine` | `Auth.current`, live on `adoptions` |

## The adoption transaction

This is the handler from the [introduction](/guide/introduction). It takes the database as a module argument only so that `[@@transactional]` knows which pool to open the transaction on.

<<< @/../examples/shelter/server/adoptions_controller.ml

The service does the work in three steps, each through an ordinary `Db.with_conn` that joins the handler's transaction: mark the cat adopted (only if it is still available), insert the adoption, then count the member's adoptions.

<<< @/../examples/shelter/server/adoptions_service.ml{24-35}

The limit check comes after the writes on purpose. When a member asks for a third cat, the cat is already marked adopted and the adoption row is inserted — and returning `Error` undoes both.

```mermaid
sequenceDiagram
  participant B as Browser
  participant H as adopt handler
  participant C as Cats_service
  participant A as Adoptions_service
  participant D as Database
  participant L as Live
  B->>H: POST /adoptions with cat_id
  H->>H: Auth.current parses the token
  H->>D: BEGIN (Db.within)
  H->>A: adopt cat_id user.id
  A->>C: adopt
  C->>D: UPDATE cats WHERE status = available
  alt no row changed
    C-->>H: Error 409 this cat is not available
    H->>D: ROLLBACK
  else the cat was available
    A->>D: INSERT adoptions
    A->>D: SELECT adoptions by user_id
    alt two or fewer
      A->>D: INSERT kre_jobs (enqueue)
      H->>D: COMMIT
      H->>L: publish cats and adoptions
      H-->>B: 201 Created
    else a third cat
      H->>D: ROLLBACK
      H-->>B: 409 a member adopts at most 2 cats
    end
  end
```

The guarded `UPDATE` is the only hand-written write in the app:

```sql
UPDATE cats SET status = @status, owner_id = @owner_id, version = version + 1
WHERE id = @id AND status = @available;
```

::: tip Rolled back means invisible
After a rollback nothing leaks: the cat is available again, no letter is queued, and no live event is published. The tests check all three.
:::

## The letter: a job and a mailer

A queue is a name plus the dto of its payload. The worker is a provider built on the same database:

<<< @/../examples/shelter/server/queues.ml

<<< @/../examples/shelter/server/jobs.ml

The handler is a function in a provider marked `[@@job Queues.congratulate]`. `[%wire]` registers it with the worker and starts the worker with the app.

<<< @/../examples/shelter/server/mailer.ml

<Flow :steps="jobFlow" caption="A letter per adoption that actually happened" />

In this example the mail provider is the in-memory outbox. `main.ml` mounts its `controller`, so every letter has a preview at `/__kre/mail`; production swaps in `Kre.Mail.Smtp`.

<<< @/../examples/shelter/server/mail.ml

## The live catalog

`GET /cats`, `GET /cats/:cat` and `GET /cats/catalog` are marked `[@@live [ "cats" ]]`; `GET /adoptions/mine` is live on `adoptions`. After a transaction commits, Kre publishes the tables it wrote, and every page whose route reads one of them reloads its data over `/__kre/live`. When one member adopts a cat, it disappears from everybody else's list without a line of subscription code.

On the client, the same tables come with the generated client as `Cats_client.Live.available`, and the router takes them as `~live`:

<<< @/../examples/shelter/client/routes.mlx

## Rename: `[@load]`, `[@@authorize]` and a version

Renaming a cat combines three borrowed patterns in one handler:

1. `~(cat : (Cat.t[@load Cats.find]))` parses `:cat` as a `Cat.Id.t` and loads the record — `None` is a 404.
2. `[@@authorize fun ~user ~cat -> Auth.owner_or_admin ~user cat]` receives the parsed user and the loaded cat.
3. The body carries the `version` the client read. The generated update only matches that version.

```sql
UPDATE cats SET name = @name, age = @age, status = @status,
  owner_id = @owner_id, version = version + 1
WHERE id = @id AND version = @version;
```

Zero affected rows means somebody else changed the cat first, and the service answers 409:

<<< @/../examples/shelter/server/cats_service.ml{57-70}

The test plays the race out: Ann owns the cat, the admin holds a stale copy, Bob owns nothing.

| Who | Version sent | Status | Why |
| --- | --- | --- | --- |
| Ann (owner) | current | 200 | owner, version matches |
| Admin | the old one | 409 | Ann already bumped the version |
| Bob (member) | current | 403 | `owner_or_admin` refuses |
| Admin | current | 200 | admins rename any cat |
| Admin, cat 999999 | — | 404 | `[@load]` found nothing |

## Commands: seed and signup

Two functions marked `[@@command]` reuse the same wired providers as the server. Their labelled arguments become command-line options, parsed with the same scalar and refined parsers as query strings — so `--email` must be a valid email.

<<< @/../examples/shelter/server/tasks.ml

```sh
./main.exe seed --count 3
./main.exe signup --email boss@shelter.test --password whiskers1
```

## Configuration and database

The config is a record read from the environment, with secrets masked in `/actuator/env`:

<<< @/../examples/shelter/server/config.ml

The database provider is the connection pool with a health check:

```ocaml
module Make (Settings : Settings.S) = struct
  include
    Kre.Db.Make
      (Kre_db_mariadb.Driver)
      (struct
        let url = Settings.config.database_url
        let size = 4
      end)
end
```

`schema/schema.ml` prints the DDL from the tables, and sqlgg checks every query against it:

```ocaml
let () =
  let tables = [ User.table; Cat.table; Adoption.table; Credential.table ] in
  print_string (Kre.Table.schema Mysql tables)
```

## The wiring graph

`bin/main.ml` is the whole composition root. `[%wire]` finds the providers and controllers, orders them by dependency and applies the functors; a missing one is a compile error.

<<< @/../examples/shelter/bin/main.ml

The graph it built is served at `/actuator/beans.mmd`:

```mermaid
graph TD
  Settings
  Database --> Settings
  Cats_service --> Database
  Jobs --> Database
  Adoptions_service --> Database
  Adoptions_service --> Cats_service
  Adoptions_service --> Jobs
  Mail
  Mailer --> Mail
  Users_service --> Settings
  Users_service --> Database
  Adoptions_controller --> Adoptions_service
  Adoptions_controller --> Database
  Auth_controller --> Users_service
  Cats_controller --> Cats_service
```

## The Melange client

The browser code never writes a URL or a JSON decoder. `client/dune` asks the server binary for its spec and runs `kre client` once per controller.

<Flow :steps="clientFlow" caption="From the server's routes to typed pages" />

The pages use the shared types directly. The cat page matches on `Cat.Status.t`, so a new status would not compile until the page handles it, and the login form parses the email with the same `Refined.Email` the server uses.

<<< @/../examples/shelter/client/pages.mlx

## How it is tested

Two executables share one MariaDB database, set by `KRE_TEST_SHELTER_URL`:

```sh
KRE_TEST_SHELTER_URL=mariadb://kre:kre@127.0.0.1:3306/shelter_test \
  dune build @examples/shelter/test/shelter
```

`test_shelter.ml` builds the app with the same `[%wire]` and calls the handler through `Dream.test` — no socket. It also reads `Mail.sent ()` from the outbox and runs commands through `Kre.Command.invoke`.

| Group | Cases | What it proves |
| --- | --- | --- |
| auth | 5 | `ADMIN_EMAIL` makes an admin, email taken is 409, short password is 422 with `min_length`, wrong password 401, forged token 401 |
| cats | 3 | only admins admit cats, the catalog pages and rejects bad `?size`, unknown cat 404 |
| adoptions | 2 | a cat is adopted once and live publishes `cats` and `adoptions`; the third adoption rolls back |
| jobs | 1 | two letters for two adoptions, none for the rolled-back one |
| commands | 1 | `seed --count 2` and `signup` run with wired providers |
| authorize | 1 | the rename table above, ending at version + 2 |

<<< @/../examples/shelter/test/test_shelter.ml

`run_scenario.ml` starts the real `bin/main.exe` on a free port and runs the compiled Melange `scenario.mlx` in node. The generated clients sign up, get a 403 and a 409 as Problem Details, adopt a cat, receive the live `cats` event and render the login page to markup. The transcript must match exactly:

```text
boss ok admin
ann ok member
ann admits problem 403 urn:kre:error:forbidden
ann adopts ok tom
again problem 409 urn:kre:error:conflict
available ok felix
live cats
login <form><input type="email" value=""/><input type="password" value=""/><button type="submit">Log in</button></form>
```

<<< @/../examples/shelter/client/scenario.mlx

::: info Where each piece is explained
[Guards & auth](/guide/guards-auth) · [Transactions](/data/transactions) · [Live loaders](/data/live) · [Background jobs](/background/jobs) · [Mail](/background/mail) · [Commands](/background/commands) · [Typed client & router](/client/client-router) · [Testing](/tooling/testing)
:::

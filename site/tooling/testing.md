# Testing

<p class="lead">There is no testing module to configure and no container to override. A controller is a function of its providers, so a test passes it fresh ones. The app is a <code>Dream.handler</code>, so a test calls it without a socket. And the generated client works in tests too, so a wrong path or field breaks the build of the test instead of failing at run time.</p>

<script setup>
const levels = [
  { title: 'ppx expect tests', sub: 'The generated code and every compile error, as text', code: 'test/ppx/*.t', tone: 'magma' },
  { title: 'Runtime units', sub: 'Error, Validation, Refined, Spec, Route', code: 'test/core', tone: 'ember' },
  { title: 'Controllers', sub: 'Dream.test with fresh providers', code: 'Cats_service.Make ()', tone: 'amber' },
  { title: 'Typed client', sub: 'The generated client, routed in-process', code: 'Kre_testing.use', tone: 'violet' },
  { title: 'Database', sub: 'Real MariaDB or Postgres, opt-in aliases', code: '@db @shelter @pg', tone: 'sky' },
  { title: 'Browser code', sub: 'The Melange client in node against a live server', code: 'run_scenario', tone: 'mint' }
]
const stats = [
  { value: '0', label: 'sockets', note: 'in controller and typed client tests' },
  { value: '1', label: 'client', note: 'the same generated module as the frontend' },
  { value: '6', label: 'levels', note: 'from ppx output to node' }
]
const compare = [
  { topic: 'Replacing a dependency', elsewhere: 'Test.createTestingModule(...).overrideProvider(...) (Nest); @MockBean (Spring)', kre: 'Pass another module to register' },
  { topic: 'Fresh state per test', elsewhere: 'A new testing module per suite', kre: 'A generative functor: Cats_service.Make ()' },
  { topic: 'Calling a route', elsewhere: 'supertest (Nest); MockMvc (Spring); request specs (Rails)', kre: 'Dream.test handler (Dream.request ...)' },
  { topic: 'Typed HTTP calls', elsewhere: 'Strings: paths, JSON bodies, expectations', kre: 'The generated client via Kre_testing.use; typos do not compile' },
  { topic: 'Database tests', elsewhere: 'Test containers or a test profile', kre: 'dune aliases with a DATABASE_URL from the environment' },
  { topic: 'Testing code generation', elsewhere: 'Not applicable: decorators are runtime metadata', kre: 'Expect tests on the ppx output and its error messages' }
]
</script>

<StatGrid :stats="stats" />

<Flow :steps="levels" caption="Six levels, from the cheapest to the most real" />

## Controller tests with `Dream.test`

`Kre.App.handler` turns a list of controllers into a `Dream.handler`, and `Dream.test` runs a request through it in memory. To isolate a test, apply the service functor once more: `Cats_service.Make ()` is generative, so `Fresh` has its own empty store.

<<< @/../examples/cats/test/test_cats.ml{1-19 ocaml}

That is the whole harness. The tests are plain Alcotest cases over status codes and bodies, and they read like a checklist of the framework's promises:

<<< @/../examples/cats/test/test_cats.ml{29-82 ocaml}

Want a fake instead of a fresh real service? Write any module with the service's signature and pass it to `register`. Nothing is overridden; you just call the function with a different argument.

::: tip The whole app, wired
When a test needs every controller with its real dependencies, use `[%wire]` in the test itself, exactly as in `main.ml`. The shelter test starts with `let app = [%wire]` and then calls `Dream.test (Kre.App.handler app.controllers)`.
:::

## Typed tests with the generated client

Nest tests HTTP with supertest and Spring with MockMvc; both build requests out of strings. A Kre test can call the very client the frontend uses. `Kre_testing.use` (library `kre-client.testing`) points the native client's requests straight at the app's handler — no port, no socket:

```ocaml
val use : ?middleware:Dream.middleware list -> Kre.Controller.t list -> unit
```

```mermaid
sequenceDiagram
  participant T as Test
  participant C as Cats_client (generated)
  participant H as Kre.App.handler
  T->>C: create ~body:tom
  C->>H: POST /cats, in memory
  H-->>C: 201 and JSON
  C-->>T: Ok (cat : Cat.t)
  T->>C: find_one ~id:9
  C->>H: GET /cats/9
  H-->>C: 404 Problem Details
  C-->>T: Error (Problem { status = 404 })
```

The test below calls the generated `Cats_client` and a hand-declared `[%http_client]`, and checks the typed outcomes, including the 422 with its field path:

<<< @/../examples/cats/client_native/test_in_process.ml

Notice what you cannot get wrong here. `Cats_client.create` takes `~body:Create_cat_dto.t`, so the test builds a typed record with refined fields. The answer is a `(Cat.t, Kre_client.Error.t) result`, so a 422 is `Problem { status; errors; _ }` with typed paths, not a string to grep.

### A declared client in tests

`Cats_api` above is declared, not generated: `[%http_client: val … [@@get "/cats/:id"]]` describes the remote API by signature, and applying it to a module with `url` and `headers` gives you an implementation. `Kre_testing.use` serves those calls too, which lets you test code that talks to another service by mounting that service's controllers in the same process. See [Calling other APIs](/client/http-client).

### Where the client comes from

The test's `dune` file generates the client from the application itself. The server binary prints its spec, and `kre client` turns the spec into a module:

<<< @/../examples/cats/client_native/dune{scheme}

## Database tests

Tests that need a real database are not part of `dune test`. Each one is a dune alias that reads its connection URL from an environment variable, so CI can provide a throwaway database and a laptop without one still runs everything else.

| Alias | Variable | Runs |
| --- | --- | --- |
| `@db` | `KRE_TEST_DB_URL` | Cats on MariaDB: a migration test, `kre migrate up`, `status`, `down` twice, then the CRUD test |
| `@shelter` | `KRE_TEST_SHELTER_URL` | The shelter suite against MariaDB, then the browser scenario against the real binary |
| `@pg` | `KRE_TEST_PG_URL` | Cats on PostgreSQL |

```sh
KRE_TEST_DB_URL=mariadb://kre:kre@127.0.0.1:3306/kre_test \
  dune build @examples/cats/db/test/db

KRE_TEST_SHELTER_URL=mariadb://kre:kre@127.0.0.1:3306/shelter_test \
  dune build @examples/shelter/test/shelter

KRE_TEST_PG_URL=postgresql://kre@127.0.0.1:5499/kre_test \
  dune build @examples/cats/postgresql/pg
```

The `@db` alias is one rule, so its steps share the database in order — and it doubles as a test of the CLI:

<<< @/../examples/cats/db/test/dune{scheme}

The shelter alias sets the rest of the environment the app expects — `JWT_SECRET`, `ADMIN_EMAIL`, `KRE_ENV=test` — and runs both executables in turn:

<<< @/../examples/shelter/test/dune{scheme}

::: warning Give each suite its own database
The suites clear their tables before they start. Point `KRE_TEST_SHELTER_URL` at a database used for nothing else.
:::

## The browser client, in node

The frontend is OCaml compiled to JavaScript by Melange. To test it for real, `run_scenario.ml` starts a server on a free port, runs the compiled scenario in node against it, and compares the transcript. The cats version serves the app from inside the test:

<<< @/../examples/cats/client_js/run_scenario.ml{1-29 ocaml}

The shelter goes one step further: it starts the real `main.exe` as a process, waits for the port, and runs `scenario.js` — signups, an admin adding cats, a member denied, an adoption and a repeated one, a live update of the available cats — against the same binary you would deploy.

```mermaid
flowchart LR
  T["run_scenario.exe"] -->|starts| S["bin/main.exe on a free port"]
  T -->|runs| N["node scenario.js"]
  N -->|"generated client over HTTP"| S
  S --> D[("MariaDB")]
  N -->|transcript| T
```

Set `NODE` to choose the node binary; the scenario uses `--experimental-eventsource` for live loaders.

## ppx expect tests

Everything the ppx generates is pinned by expect tests in `test/ppx/*.t`: the input, the exact output, and every error message with its location. They are the best reference for what an attribute does, and they are what this documentation quotes in its warning boxes. A typical one, from `retry.t`:

```sh
$ cat > input.ml <<'ML'
> let fetch = Weather.get [@@retry 3]
> ML
$ ./pp.exe -impl input.ml
File "input.ml", line 1, characters 24-35:
1 | let fetch = Weather.get [@@retry 3]
                            ^^^^^^^^^^^
Error: [@@retry] repeats a call; put it on a function: let f x = … [@@retry 3]
[1]
```

Change the ppx and `dune test` shows the diff; `dune promote` accepts it.

## How it compares

<Compare :rows="compare" left="NestJS / Spring / Rails" right="Kre" />

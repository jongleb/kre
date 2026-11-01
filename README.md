# Kre

A typed full-stack web framework for OCaml 5.5: [Dream](https://github.com/aantron/dream) on the server, [Melange](https://melange.re) in the browser, and ppx rewriters that turn attributes into plain code at build time.

One record type is the database table, the JSON schema, the validator, the HTTP client type and the page's search parameters. A missing provider, a wrong route parameter or a broken link is a compile error, not a 500.

```ocaml
[@@@controller "cats"]

let find_one (module Cats : Cats_service.S) ~(cat : (Cat.t[@load Cats.find])) :
    Cat.t Lwt.t =
  Lwt.return cat
[@@get ":cat"] [@@live [ "cats" ]]

let create (module Cats : Cats_service.S) ~(body : Create_cat_dto.t) :
    Cat.t Lwt.t =
  Cats.create body
[@@post] [@@status 201] [@@role Auth.admin] [@@summary "Admit a cat"]

let rename (module Cats : Cats_service.S)
    ~user:(_ : (User.t[@guard Auth.current])) ~(cat : (Cat.t[@load Cats.find]))
    ~(body : Rename_dto.t) : (Cat.t, Kre.Error.t) result Lwt.t =
  Cats.rename cat.id body
[@@put ":cat"] [@@authorize fun ~user ~cat -> Auth.owner_or_admin ~user cat]
```

`:cat` is parsed as `Cat.Id.t` and loaded (404 if absent), the body is validated (422 with every error at once), guards return evidence instead of booleans, and the whole application is assembled by `[%wire]` from the modules it finds — at build time.

## What is inside

- **Controllers** — routes, typed path, query, header, cookie and body parameters, guards, `[@@authorize]`, `[@@transactional]`, ETags, response caching, server-sent events, WebSocket gateways, signed links, API tokens with abilities, `[%%resource]` CRUD in one item.
- **Data** — `[@@deriving dto]` (validation, views, mapped types), `[@@deriving table]` (DDL, typed rows, timestamps, versions, slugs, ULIDs, embedded records, filters, scopes, pages) with [sqlgg](https://github.com/ygrek/sqlgg) for typed SQL on MariaDB and PostgreSQL.
- **Dependency injection** — services are modules, dependencies are functor parameters, `[%wire]` resolves them at build time, with decorators, collections and per-environment providers.
- **Background work** — jobs in the same database, schedules checked at build time, events, commands on the server binary, locks, retries, mail with an outbox preview.
- **Tooling** — typed client and OpenAPI 3.1 generated from the controllers, the `kre` CLI (`new`, `generate`, `client`, `openapi`, `routes`), actuator endpoints, a request profiler, a jobs dashboard.
- **Client** — Melange pages in mlx (OCaml with JSX), a typed router, live loaders that reload when a table changes, `[%asset]` and `[%icon]` checked at build time.

## Getting started

```sh
git clone https://github.com/jongleb/kre.git && cd kre
opam switch create . 5.5.1 --deps-only --with-test
eval $(opam env --switch=. --set-switch)
npm ci
dune build @all && dune test
```

The database examples need a server: `KRE_TEST_SHELTER_URL=mariadb://… dune build @examples/shelter/test/shelter`, `KRE_TEST_PG_URL=postgresql://… dune build @examples/cats/postgresql/pg`.

## Layout

| Path | What |
| --- | --- |
| `src/core` | `Kre`, the server runtime |
| `src/shared` | `Kre_shared`, built natively and with Melange |
| `src/ppx` | the ppx rewriters |
| `src/client` | `Kre_client`: HTTP, router, pages |
| `src/db` | MariaDB and PostgreSQL drivers |
| `src/cli` | the `kre` command |
| `examples/shelter` | a whole application: auth, roles, jobs, tokens, Melange client |
| `examples/cats` | the running example of the docs |
| `docs/` | chapters whose code is checked by mdx |
| `site/` | the documentation site (`cd site && npm ci && npm run dev`) |
| `DESIGN.md` | the design, signatures and phases |

## License

ISC

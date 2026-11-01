# Migrations

<p class="lead">Migrations are plain SQL files with an up and a down section. The server embeds them at build time and applies the pending ones on start, the <code>kre</code> CLI applies them by hand, and a dune rule compares them with the schema your records print — so a table that changed without a migration fails <code>dune test</code>.</p>

<script setup>
const loop = [
  { title: "Change a record", sub: "Add a field with [@@deriving table]", tone: "ember" },
  { title: "dune test", sub: "schema.exe prints the migration; the diff fails", tone: "magma" },
  { title: "dune promote", sub: "Writes the new SQL into migrations/", tone: "amber" },
  { title: "dune build", sub: "[%embed_dir] bakes the files into the binary", tone: "violet" },
  { title: "Server start", sub: "on_start runs Kre.Migration.up", tone: "mint" }
]
const stats = [
  { value: "2", label: "sections per file", note: "-- migrate:up and -- migrate:down" },
  { value: "4", label: "CLI commands", note: "up, down, status, new" },
  { value: "1", label: "bookkeeping table", note: "kre_migrations (version, applied_at)" }
]
const compare = [
  { topic: "Format", elsewhere: "Flyway: V1__init.sql. Rails: Ruby DSL. TypeORM: a class with up() and down()", kre: "NNNN_name.sql with -- migrate:up and -- migrate:down" },
  { topic: "Applying on start", elsewhere: "Spring Boot runs Flyway automatically. TypeORM: migrationsRun: true", kre: "Kre.Migration.up in a provider's on_start" },
  { topic: "Shipping the files", elsewhere: "On the classpath or next to the app", kre: "Embedded in the binary by [%embed_dir]" },
  { topic: "Keeping in sync with the model", elsewhere: "typeorm migration:generate, rails db:schema:dump", kre: "A dune diff rule: dune test fails, dune promote fixes it" },
  { topic: "Command line", elsewhere: "flyway migrate, rails db:migrate, typeorm migration:run", kre: "kre migrate up | down | status | new" }
]
</script>

<StatGrid :stats="stats" />

## A migration file

A migration is a file in `migrations/` named `NNNN_name.sql`. It has two sections:

<<< @/../examples/cats/db/migrations/0002_owners.sql{sql}

The rules are short:

- Files run in name order; the name without `.sql` is the version.
- A statement ends with `;` at the end of a line. Lines that start with `--` are skipped.
- `-- migrate:up` is required and must contain at least one statement. `-- migrate:down` may be empty.
- Applied versions are recorded in `kre_migrations (version, applied_at)`, created on first use.

::: warning MariaDB commits DDL implicitly
On MariaDB each `CREATE` or `ALTER` commits on its own, so a migration with several statements is not atomic. If one fails halfway, the earlier statements stay applied and the version is not recorded. Keep migrations small.
:::

## The command line

```sh
kre migrate new add_owners        # creates migrations/0003_add_owners.sql
kre migrate status                # pending  0003_add_owners
kre migrate up                    # applied 0003_add_owners
kre migrate down                  # rolled back 0003_add_owners
```

`up` applies every pending migration in order; `down` rolls back the last applied one. Point them at a database with `--url mariadb://user:pass@host:port/db` or the `DATABASE_URL` variable, and at a directory with `--dir` (default `migrations`). `new` only needs `--dir`.

## Migrating on start

In an application you rarely run the CLI. The database provider applies pending migrations in its `on_start` hook, and `[%wire]` calls that hook before the server listens:

<<< @/../examples/shelter/server/database.ml{10-17}

`[%embed_dir "migrations"]` expands at build time into a list of `(file name, contents)` pairs, so the server does not depend on its working directory and a deployed binary carries its own schema history. Tell dune the ppx reads those files:

<<< @/../examples/shelter/server/dune{scheme}

The `Kre.Migration` API is small and works over any `Kre.Db.DRIVER`:

<<< @/../src/core/migration.mli

## The schema is checked against the migrations

This is where Kre goes further than most frameworks. The records are the truth, and `schema.exe` can print the migration they imply. A dune rule prints it and diffs it against the file in `migrations/`:

```scheme
; examples/shelter/server/sql/dune
; The migrations are the schema: change a table without a migration and this
; diff fails; `dune promote` writes the new one.

(rule
 (targets init.sql jobs.sql)
 (action
  (progn
   (with-stdout-to
    init.sql
    (run %{exe:../../schema/schema.exe} migration app))
   (with-stdout-to
    jobs.sql
    (run %{exe:../../schema/schema.exe} migration jobs)))))

(rule
 (alias runtest)
 (action
  (progn
   (diff ../migrations/0001_init.sql init.sql)
   (diff ../migrations/0002_jobs.sql jobs.sql))))
```

<Flow :steps="loop" caption="Change a table, get a migration" />

Add a field to `Cat.t` and forget the migration, and `dune test` fails with a diff that shows exactly the `CREATE TABLE` line that changed. `dune promote` copies the generated SQL into `migrations/`. You read it, adjust it if needed, and commit it.

```mermaid
flowchart LR
  R["Cat.t with [@@deriving table]"] --> S["schema.exe migration app"]
  S --> G["_build/.../init.sql"]
  M["migrations/0001_init.sql"] --> D{"dune test: diff"}
  G --> D
  D -- equal --> OK["build passes"]
  D -- different --> F["test fails"]
  F -- "dune promote" --> M
```

::: info While the example is unreleased
The shelter regenerates `0001_init.sql` in place because no database runs it yet. Once an application ships, migrations are only ever added: a new file per change, never an edit to an applied one.
:::

## The jobs table

[Background jobs](/background/jobs) live in one table, `kre_jobs`, described by `Kre.Job.table` like any other table. The same `schema.exe` prints its migration (`schema.exe migration jobs`), and the same diff rule keeps it honest:

<<< @/../examples/shelter/server/migrations/0002_jobs.sql{sql}

## PostgreSQL

`Kre.Migration` takes the driver as a first-class module, so the Postgres driver works the same way:

```ocaml
Kre.Migration.up (module Kre_db_postgresql.Driver) conn migrations
```

Write the SQL in the Postgres dialect — `SERIAL` instead of `AUTO_INCREMENT`, a separate `CREATE INDEX` — or print it with `Kre.Table.schema Postgresql`. The `kre migrate` CLI connects through the MariaDB driver; on Postgres, apply migrations from the application's `on_start`.

## How it compares

<Compare :rows="compare" left="Flyway / Rails / TypeORM" right="Kre" />

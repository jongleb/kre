# Introduction

<p class="lead">kre is a full-stack web framework for OCaml. Controllers, services, guards and DTOs are ordinary functions, modules, functors and ppx attributes, so the compiler sees your whole application: the routes, the dependencies, the SQL, the wire format and the frontend.</p>

<StatGrid :stats="[
  { value: '0', label: 'classes or reflection', note: 'modules and functors only' },
  { value: '1', label: 'source of truth', note: 'the record in shared/' },
  { value: '2', label: 'targets', note: 'native server, Melange browser' }
]" />

## A handler is a function

Its labelled arguments say where each value comes from, its module arguments name the services it needs, and its return type decides the response. Attributes next to it add behaviour that applies around it.

<<< @/../examples/shelter/server/adoptions_controller.ml

Everything around that function — route matching, parsing, guards, the transaction, the JSON — is generated at compile time by `kre-ppx`:

<RequestPipeline />

## Three rules

<Flow :steps="[
  { title: 'Types are the truth', sub: 'Tables, JSON, OpenAPI and clients are derived from records.' },
  { title: 'Wiring is compiled', sub: 'Providers are functors that [%wire] applies at build time.' },
  { title: 'Parse at the edge', sub: 'Input becomes a refined type once; the core never re-checks.' }
]" />

### Types are the truth

A record in `shared/` is compiled twice: natively for the server and to JavaScript for the browser. `[@@deriving table, dto]` turns it into a table description, a JSON codec with validation and a JSON Schema. The SQL schema, the OpenAPI document and the browser client all come from there.

<TypeFanout />

### Wiring is compiled

There is no container to configure. A service that needs a database is a functor over a database module; a controller that needs the service takes it as a module argument. `[%wire]` in `main.ml` scans the application, sorts the functors by dependency and applies them. A missing provider, two candidates for one interface or a cycle stop the build with the location of the problem.

### Parse at the edge

`Cat.Name.t` is not a string with a check somewhere — it is a type you can only get by parsing. Request bodies, path segments, query strings and command-line options all go through the same parsers, and failures come back as RFC 9457 Problem Details with the path of every bad field.

## What the build checks

<CompileVsRuntime />

## How it fits together

<Layers />

## Next

::: tip Start building
[Getting started](/guide/getting-started) creates a project with `kre new`, adds a resource with `kre generate` and runs it.
:::

::: info See a whole application
[The shelter tour](/reference/shelter) walks through a complete app: users, cats and adoptions with auth, transactions, live pages, jobs, mail and a typed frontend.
:::

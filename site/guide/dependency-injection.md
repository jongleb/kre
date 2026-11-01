<script setup>
const facts = [
  { value: '3', label: 'provider shapes', note: 'singleton, Make (), Make (Deps)' },
  { value: '3', label: 'build errors', note: 'missing, ambiguous, cycle' },
  { value: '0', label: 'tokens, decorators, reflection', note: 'module types are the tokens' }
]

const wireSteps = [
  { title: 'Scan', sub: 'Every .ml under the app directory, skipping test/ and _build/', tone: 'sky' },
  { title: 'Classify', sub: 'Providers, controllers, everything else ignored', tone: 'violet' },
  { title: 'Resolve', sub: 'Each functor parameter to exactly one provider', tone: 'amber' },
  { title: 'Sort', sub: 'Topologically; a cycle stops the build', tone: 'magma' },
  { title: 'Apply', sub: 'let module X = X.Make (Deps) in …', tone: 'ember' },
  { title: 'Return', sub: 'Kre.Wiring.t: controllers, hooks, health, beans', tone: 'mint' }
]

const compare = [
  { topic: 'Declare a provider', elsewhere: '@Injectable() / @Service', kre: 'A module with module type S, or a Make functor' },
  { topic: 'Declare dependencies', elsewhere: 'Constructor parameters, resolved at startup', kre: 'Functor parameters, resolved at compile time' },
  { topic: 'Find components', elsewhere: '@Module({ providers }) / @ComponentScan', kre: '[%wire] scans the directories' },
  { topic: 'Two implementations', elsewhere: '@Primary, @Qualifier, custom tokens', kre: '[@@@primary], or the parameter name' },
  { topic: 'Default implementation', elsewhere: '@ConditionalOnMissingBean, @Optional', kre: '[@@@fallback]' },
  { topic: 'Missing dependency', elsewhere: 'Error when the app starts', kre: 'Error when the app compiles' },
  { topic: 'Circular dependency', elsewhere: 'forwardRef or @Lazy', kre: 'Not expressible; a build error names the cycle' },
  { topic: 'Inspect the graph', elsewhere: '/actuator/beans, Nest Devtools', kre: '/actuator/beans and beans.mmd, built at compile time' }
]
</script>

# Dependency injection

<p class="lead">In Kre a service is a module, a service with dependencies is a functor, and an interface is a module type. <code>[%wire]</code> finds them all at build time, applies the functors in dependency order and hands you a ready application. A missing provider, an ambiguity or a cycle is a compile error with a file and line.</p>

<StatGrid :stats="facts" />

## Why there is no container

NestJS has `@Module`, a DI container, injection tokens and `forwardRef`. Spring has component scanning, bean definitions and proxies. Both exist to make up for a language that cannot say "a cats service, given some database". OCaml can: that is a functor. So Kre maps every DI concept onto what the language already has:

| Concept | NestJS / Spring | Kre |
| --- | --- | --- |
| interface, injection token | abstract class, `@Qualifier` | `module type S` |
| singleton provider | `@Injectable()`, `@Service` | a module whose `.mli` includes `S` |
| provider with dependencies | constructor injection, `@Autowired` | `module Make (Db : Kre.Db.S) = …` |
| exports | `exports: [...]` | the `.mli` |
| imports | `imports: [...]` | the functor parameters and dune `(libraries …)` |
| the application module | `AppModule`, `@SpringBootApplication` | `bin/main.ml` with `[%wire]` |
| consumer | a controller's constructor | `(module Cats : Cats_service.S)` on a handler |

## Three shapes of provider

### A singleton: `module type S`

A module that defines `module type S` and implements it at the top level is a singleton. The module itself is the instance. The shelter's configuration is one:

<<< @/../examples/shelter/server/settings.mli

<<< @/../examples/shelter/server/settings.ml

### A fresh instance: `Make ()`

A generative functor with an empty argument creates new state every time it is applied, like `new CatsService()`. `include Make ()` gives the module a default instance, and tests can make their own:

<<< @/../examples/cats/server/cats_service.mli

```ocaml
let module Fresh = Cats_service.Make () in
Dream.test (Kre.App.handler [ Cats_controller.register (module Fresh) ])
```

### With dependencies: `Make (Db : …)`

A functor's parameters are its constructor injection. The connection pool needs the settings:

<<< @/../examples/shelter/server/database.mli

The adoptions service needs the pool, the cats service and the job queue:

<<< @/../examples/shelter/server/adoptions_service.mli

The **interface** a provider implements is the annotation on its `Make` result (in the `.ml` or the `.mli`), such as `: S` or `: Kre.Job.S`, or otherwise its own `module type S`. When a module only includes something, say so with `[@@@injectable Iface.S]`:

<<< @/../examples/shelter/server/mail.ml

A module that has `module type S` and nothing else is an interface, not a provider.

## Consumers: controllers

Controllers do not declare dependencies anywhere except on the handlers that use them. All module parameters of a file are merged by name and become the parameters of the generated `register`:

<<< @/../examples/shelter/server/adoptions_controller.ml{3-4}

Here `register` takes `(module Adoptions)` and `(module Db)`; `[@@transactional]` uses the `Db` dependency to open the transaction. See [Controllers](/guide/controllers).

## `[%wire]`: compile-time component scan

The composition root is one line:

<<< @/../examples/cats/bin/main.ml{2}

<Flow :steps="wireSteps" caption="What [%wire] does during the build" />

Like `@SpringBootApplication`, `[%wire]` scans the application directory — the parent of the directory holding `main.ml` — recursively. It skips `test`, `tests`, `_build`, `node_modules` and hidden directories. Copies of one module made by `copy_files#` for Melange are merged by name. To scan only some directories, list them: `[%wire "server"; "db"]`.

| In the file | Role | Nest / Spring |
| --- | --- | --- |
| `module type S` with a top-level implementation | singleton provider | `@Service` |
| `module Make () = …` | provider, new instance | `@Injectable`, `@Scope(PROTOTYPE)` |
| `module Make (Db : Kre.Db.S) (Clock : Clock.S) = …` | provider with dependencies | `@Autowired` constructor |
| `[@@@controller "…"]` | consumer: handlers' module parameters go to `register` | `@Controller` |
| `[@@@gateway "…"]` | consumer, for WebSockets | `@WebSocketGateway` |
| anything else | left alone | — |

Two things are needed in dune: the ppx on `main.ml`, and a dependency on the sources it reads so the app is re-wired when they change. The modules it finds must be visible from `main`, so the libraries are `(wrapped false)`:

<<< @/../examples/cats/bin/dune{dune}

### What it generates

For a small app with a repository, a clock, a report that needs both and a controller, `[%wire "app"]` expands to plain functor applications:

```ocaml
let app =
  let module Repo = (Repo.Make)() in
  let module Report = ((Report.Make)(Repo))(Clock) in
  Kre.Wiring.make
    ~controllers:[Reports_controller.register (module Report)]
    ~on_start:[Report.on_start] ~on_shutdown:[] ~jobs:[] ~health:[]
    ~commands:[]
    ~beans:[{ Kre.Actuator.name = "Clock"; needs = [] };
            { Kre.Actuator.name = "Repo"; needs = [] };
            { Kre.Actuator.name = "Report"; needs = ["Repo"; "Clock"] };
            { Kre.Actuator.name = "Reports_controller"; needs = ["Report"] }] ()
```

Nothing happens at runtime that you could not have written by hand. The type checker then verifies every application, so a provider whose signature does not match is an ordinary type error.

### What you get back

`[%wire]` returns a `Kre.Wiring.t`:

<<< @/../src/core/wiring.mli{1-11}

The shelter passes every field on:

<<< @/../examples/shelter/bin/main.ml

## Choosing between providers

When exactly one provider implements an interface, it is used. Otherwise `[%wire]` decides in this order:

```mermaid
flowchart TD
  Q["Report needs Clock.S"] --> F["Drop [@@@fallback] providers<br/>if any other one exists"]
  F --> N{"How many are left?"}
  N -->|"none"| E1["Build error: no provider"]
  N -->|"one"| OK["Use it"]
  N -->|"several"| P{"Exactly one [@@@primary]?"}
  P -->|"yes"| UP["Use the primary"]
  P -->|"no"| NM{"Parameter named after one?"}
  NM -->|"(Clock : Clock.S)"| UC["Use Clock"]
  NM -->|"no"| E2["Build error: ambiguous"]
```

**`[@@@primary]`** is Spring's `@Primary`. The `cats` example has an in-memory `Cats_service` and a database-backed `Cats_db_service`; the database one wins:

<<< @/../examples/cats/db/cats_db_service.ml{1-4}

**`[@@@fallback]`** is `@ConditionalOnMissingBean`: the provider is created and used only when nothing else implements the interface. A frozen clock for development, replaced automatically once a real one exists:

```ocaml
[@@@fallback]
module Make () : Clock.S = struct let now () = 0. end
```

**The parameter name** settles the rest, as Spring falls back to the bean name. `Make (Clock : Clock.S)` picks the provider called `Clock`; `Make (C : Clock.S)` does not pick anything.

## Errors at build time

Every wiring mistake stops `dune build` with a location. These are the exact messages:

::: danger No provider
```text
File "./app/report.ml", line 1, characters 0-49:
Error: Report needs Clock.S, but no provider gives it: add a module with Make or module type S that implements it
```
:::

::: danger Two providers, no tie-breaker
```text
File "./app/report.ml", line 1, characters 0-49:
Error: Report needs Clock.S and 2 providers give it (Clock, Fake_clock); mark one [@@@primary] or name the parameter after one
```
:::

::: danger A cycle
```text
File "./app/clock.ml", line 1, characters 0-47:
Error: dependency cycle: Clock -> Report -> Clock
```
:::

The same checks cover other things `[%wire]` collects: an `[@@on_event]` listener without a `Kre.Events.S` provider is a "no provider" error, and a `[@@cron]` expression is parsed at build time (`[@cron "61 * * * *"]: minute 61 is outside 0-59`).

## Lifecycle hooks

A provider that defines `on_start` or `on_shutdown` (and exposes it in its signature) gets them called: `on_start` in dependency order before the server accepts requests, `on_shutdown` in reverse order after SIGINT or SIGTERM. They are `@PostConstruct` and `@PreDestroy`, or `onModuleInit` and `onApplicationShutdown`.

The shelter's database runs its migrations on start and reports its health:

<<< @/../examples/shelter/server/database.ml{10-17,19-27}

```mermaid
sequenceDiagram
  participant M as main.ml
  participant D as Database
  participant J as Jobs
  participant S as Dream
  M->>D: on_start (run migrations)
  M->>J: on_start (start workers)
  M->>S: serve requests
  Note over S: SIGINT or SIGTERM
  S->>J: on_shutdown (stop workers)
```

`[@@health "db"]` marks a provider function of type `unit -> (unit, string) result Lwt.t`. `[%wire]` collects them into `app.health`, and `/actuator/health` answers `200 up` or `503 down` with the reason. Without `[%wire]`, the same hooks are plain arguments: `Kre.App.run ~on_start ~on_shutdown`.

## The graph, live

`app.beans` lists the providers in start order, then the controllers, each with what it received. `Kre.Actuator.make ~beans:app.beans` serves it as JSON at `/actuator/beans` and as a mermaid diagram at `/actuator/beans.mmd`. Here is the shelter's, exactly as `beans.mmd` prints it (an arrow points from a module to what it needs):

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

It is Spring's `/actuator/beans` and the Nest Devtools module graph, except that it was computed by the compiler, so it is exactly what was applied. See [Actuator & profiler](/tooling/observability).

## Scopes and substitutes

| Nest | Kre |
| --- | --- |
| `Scope.DEFAULT` | a module or an applied functor |
| `Scope.TRANSIENT` | a plain function |
| `Scope.REQUEST` | a `Dream.field` set by middleware and read by a `[@guard]`; services take it as a function argument, so nothing "bubbles" |
| `useValue`, `useClass` | another module with the same signature |
| `useFactory`, async providers | ordinary code in `main.ml` before `Kre.App.run`, or an `on_start` hook |
| `forRoot(config)` | a functor over a config module: `Kre.Db.Make (Driver) (struct let url = … let size = 4 end)` |

Substituting by hand is just passing a different module:

<<< @/../docs/examples/composition.ml

## How it compares

<Compare :rows="compare" left="NestJS / Spring" right="Kre" />

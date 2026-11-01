<script setup>
const rule = [
  { title: "Find the pattern", sub: "A feature that works well in a big framework", tone: "sky" },
  { title: "Keep the result", sub: "What the user of that feature actually gets", tone: "mint" },
  { title: "Drop the machinery", sub: "Proxies, reflection, runtime registries", tone: "magma" },
  { title: "Rebuild it", sub: "A function, a module, a functor or a ppx rewrite", tone: "amber" },
  { title: "Check it at build", sub: "Mistakes become compile errors with a location", tone: "ember" }
]

const nest = [
  { topic: "Controllers", elsewhere: "A class with @Controller(\"cats\") and @Get(\":id\") on methods", kre: "[@@@controller \"cats\"] on a file and [@@get \":id\"] on a plain function" },
  { topic: "Modules and DI", elsewhere: "@Module imports and providers, resolved by a container at startup", kre: "[%wire] scans the app at build time and applies functors in order" },
  { topic: "Providers", elsewhere: "@Injectable class with constructor injection", kre: "A module with Make (Db : Kre.Db.S) or a module type S" },
  { topic: "Lifecycle hooks", elsewhere: "onModuleInit, onApplicationShutdown", kre: "let on_start and let on_shutdown in the provider" },
  { topic: "Guards", elsewhere: "CanActivate returns true or false", kre: "Guard.check returns a typed value, for example Auth.Admin.t" },
  { topic: "Pipes and validation", elsewhere: "ValidationPipe plus class-validator decorators", kre: "The parameter type is the parser: [@@deriving dto], Refined, Id" },
  { topic: "Interceptors", elsewhere: "@UseInterceptors with an RxJS pipeline", kre: "[@@intercept] with logging, timeout, map_error, tap" },
  { topic: "Exception filters", elsewhere: "@Catch and @UseFilters", kre: "error_handler and [@@error_handler h], answering with Problem Details" },
  { topic: "Query DTO", elsewhere: "@Query() dto", kre: "~(search : (Cat_search.t[@search])), shared with the client and the page router" },
  { topic: "Gateways and SSE", elsewhere: "@WebSocketGateway, @SubscribeMessage, @Sse", kre: "[@@@gateway \"chat\"], [@@subscribe \"say\"], [@@sse]" },
  { topic: "OpenAPI", elsewhere: "@nestjs/swagger decorators", kre: "kre openapi from the same spec; [@@summary] and [@@description]" },
  { topic: "Events and cron", elsewhere: "@OnEvent, @Cron, @Interval", kre: "Kre.Events with [@@on_event], [@@cron] checked at build, [@@interval]" },
  { topic: "Testing module", elsewhere: "Test.createTestingModule plus supertest", kre: "Kre_testing.use: the generated client calls the handler without a socket" },
  { topic: "Scaffolding", elsewhere: "nest g resource", kre: "kre generate controller dogs name:string age:int" },
  { topic: "Calling other APIs", elsewhere: "HttpModule and HttpService", kre: "[%http_client: ...] turns a signature into a functor over a base URL" },
  { topic: "Module graph", elsewhere: "Devtools draws the graph from the running app", kre: "app.beans from [%wire], served at /actuator/beans and /actuator/beans.mmd" }
]

const spring = [
  { topic: "Transactions", elsewhere: "@Transactional through an AOP proxy; self-invocation skips it", kre: "[@@transactional] rewritten by the ppx; services join via Db.with_conn" },
  { topic: "Method security", elsewhere: "@PreAuthorize(\"#id == principal.id\"), a SpEL string", kre: "[@@authorize fun ~user ~cat -> ...], a typed function over parsed arguments" },
  { topic: "Error format", elsewhere: "ProblemDetail, RFC 9457", kre: "Every Kre.Error.t is application/problem+json; the client parses the same shape" },
  { topic: "Actuator", elsewhere: "/actuator/health, info, env, metrics, beans", kre: "Kre.Actuator.make: health, info, env with secrets masked, routes, openapi, metrics, beans" },
  { topic: "Profiles", elsewhere: "@Profile and application-dev.yml", kre: "Kre.Config.profile () reads config/default.env, then config/$KRE_ENV.env" },
  { topic: "Configuration", elsewhere: "@ConfigurationProperties, @Value", kre: "[@@deriving config] with [@env], [@default], [@secret]" },
  { topic: "Choosing a bean", elsewhere: "@Primary, @Qualifier, @ConditionalOnMissingBean", kre: "[@@@primary], the functor parameter name, [@@@fallback]" },
  { topic: "Derived queries", elsewhere: "findByStatus parsed from a method name at runtime", kre: "Table.crud prints by_<column> for [@unique], [@index], [@references]; sqlgg types them" },
  { topic: "Paging", elsewhere: "Pageable and Page<T>", kre: "Kre_shared.Page: Request.t via [@search], a t with total, -- @page in crud" },
  { topic: "Optimistic locking", elsewhere: "@Version and auditing annotations", kre: "[@version], [@created_at], [@updated_at]; a stale update is a 409" },
  { topic: "Retries", elsewhere: "@Retryable with @Backoff", kre: "[@@retry 3] [@@backoff 0.1] on any function, through Kre.Retry" },
  { topic: "HTTP interfaces", elsewhere: "@HttpExchange on an interface", kre: "[%http_client: val user : login:string -> User.t [@@get \"/users/:login\"]]" },
  { topic: "ETags", elsewhere: "ShallowEtagHeaderFilter", kre: "[@@etag] on a GET: If-None-Match gives 304" },
  { topic: "Entity parameters", elsewhere: "DomainClassConverter turns an id into an entity", kre: "~(cat : (Cat.t[@load Cats.find])): the id parses, the loader runs, missing is 404" },
  { topic: "State machines", elsewhere: "Spring Statemachine configuration beans", kre: "[@@deriving workflow] with [@@transitions], checked by the compiler" },
  { topic: "Startup tasks", elsewhere: "CommandLineRunner", kre: "[@@command \"...\"]: main.exe seed --count 3 with wired providers" },
  { topic: "Web tests", elsewhere: "MockMvc", kre: "Kre_testing.use and Dream.test against the real handler" }
]

const rails = [
  { topic: "Finders", elsewhere: "find_by and where on ActiveRecord", kre: "Generated by_<column> queries, checked by sqlgg against the schema" },
  { topic: "Conditional GET", elsewhere: "fresh_when and stale?", kre: "[@@etag] and Kre.Etag.middleware" },
  { topic: "Timestamps", elsewhere: "created_at and updated_at filled by callbacks", kre: "[@created_at] and [@updated_at] columns of type Kre_shared.Time.t" },
  { topic: "lock_version", elsewhere: "StaleObjectError at save", kre: "[@version]: UPDATE ... WHERE version = @version, zero rows means 409" },
  { topic: "Loading records", elsewhere: "before_action :set_cat", kre: "[@load Cats.find] on the parameter; [@@authorize] receives the record" },
  { topic: "Scaffold", elsewhere: "rails g scaffold", kre: "kre generate controller with typed fields; the project builds and its test passes" },
  { topic: "State machines", elsewhere: "AASM, guarded by runtime checks", kre: "[@@deriving workflow]: a typo in a transition is a compile error" },
  { topic: "Dev insight", elsewhere: "The dev log and Bullet for N+1", kre: "Kre.Profiler at /__kre/profiler, flags 3+ identical queries" },
  { topic: "Mail", elsewhere: "ActionMailer and mailer previews", kre: "Kre.Mail with Smtp and Outbox (); previews at /__kre/mail" },
  { topic: "Jobs", elsewhere: "ActiveJob with Solid Queue", kre: "Kre.Job: typed queues in one kre_jobs table, SKIP LOCKED" },
  { topic: "Tasks", elsewhere: "rake tasks and rails runner", kre: "[@@command] functions with labelled options" },
  { topic: "Pagination", elsewhere: "kaminari", kre: "Kre_shared.Page, the same type on server and client" }
]

const symfony = [
  { topic: "Entity mapping", elsewhere: "#[MapEntity] resolves an argument through Doctrine", kre: "[@load Cats.find]: a loader you wrote, chosen by name, 404 on None" },
  { topic: "Query mapping", elsewhere: "#[MapQueryString] into a DTO", kre: "[@@deriving search, dto] and [@search]; one codec on server, client and router" },
  { topic: "Workflow", elsewhere: "Workflow component configured in YAML", kre: "[@@deriving workflow] with apply, allowed, sources and a mermaid diagram" },
  { topic: "Profiler", elsewhere: "Web Profiler toolbar", kre: "Kre.Profiler: per-request SQL, timing, status, N+1 marks; dev only" },
  { topic: "Console", elsewhere: "#[AsCommand] classes", kre: "[@@command] functions; options parsed by Kre_shared.Scalar" },
  { topic: "Messenger", elsewhere: "Messenger transports with retry strategy", kre: "Kre.Job with doubling delays, dead after the last attempt" },
  { topic: "Mailer", elsewhere: "Symfony Mailer", kre: "Kre.Mail: a letter needs a Refined.Email.t recipient by construction" },
  { topic: "HTTP client", elsewhere: "HttpClient", kre: "[%http_client], native and Melange" },
  { topic: "Not modified", elsewhere: "Response::isNotModified", kre: "[@@etag]" },
  { topic: "Finders and paging", elsewhere: "findBy and Pagerfanta", kre: "by_<column>, count and page in Table.crud" },
  { topic: "CRUD maker", elsewhere: "make:crud", kre: "kre generate controller" },
  { topic: "Functional tests", elsewhere: "WebTestCase", kre: "Kre_testing.use with the generated client" }
]

const ihp = [
  { topic: "Auto Refresh", elsewhere: "Tracks tables read while rendering, at runtime, via LISTEN/NOTIFY", kre: "[@@live [\"cats\"]] declared per route, published after commit, checked in KRE_ENV=test" },
  { topic: "Jobs", elsewhere: "One table per job type", kre: "One kre_jobs table and typed queues: Kre.Job.queue \"congratulate\" (module Adoption)" },
  { topic: "Scripts", elsewhere: "Scripts run with the app context", kre: "[@@command]: the same providers as the server, wired by [%wire]" },
  { topic: "Mail", elsewhere: "IHP Mail", kre: "Kre.Mail and the Outbox preview" },
  { topic: "Source of truth", elsewhere: "Schema.sql generates the types", kre: "The OCaml record generates the schema; migrations are diffed against it" },
  { topic: "Type safety everywhere", elsewhere: "Haskell types across controllers and views", kre: "One shared/ library compiled natively and to JavaScript" }
]

const notTaken = [
  { topic: "Runtime container", elsewhere: "Nest and Spring resolve providers at startup by token or type", kre: "[%wire] at build time; a missing provider is a compile error" },
  { topic: "AOP proxies", elsewhere: "Spring wraps beans; calls from inside the bean bypass the advice", kre: "ppx rewrites the handler itself; there is no proxy to bypass" },
  { topic: "ActiveRecord callbacks", elsewhere: "after_save hooks run side effects you cannot see at the call site", kre: "A service function, or Kre.Events with a typed topic" },
  { topic: "Doctrine lifecycle events", elsewhere: "prePersist and postUpdate listeners on the entity manager", kre: "The same: explicit code in the service" },
  { topic: "Flex recipes, autoconfiguration", elsewhere: "Installing a package changes the app by itself", kre: "Every provider is a file the wiring found; app.beans shows them all" },
  { topic: "Concerns and bundles", elsewhere: "Mixins and bundle classes", kre: "OCaml modules and dune libraries" },
  { topic: "HATEOAS", elsewhere: "Links in every response", kre: "A typed client and router know the routes already" },
  { topic: "forwardRef, ModuleRef", elsewhere: "Escape hatches for cycles and lookup by token", kre: "Cycles are build errors; dependencies are passed explicitly" }
]
</script>

# What we borrowed

<p class="lead">Kre did not invent its feature list. It took the patterns people love in NestJS, Spring, Rails, Symfony and IHP, kept what they give you, and rebuilt each one from functions, modules, functors and ppx — so that the mistakes those frameworks catch at runtime are caught by the compiler.</p>

<Borrowed />

## The rule for borrowing

Every idea went through the same filter. If the original depends on runtime magic — a proxy, reflection, a registry filled at startup — Kre keeps the behaviour and replaces the mechanism with something the build can check.

<Flow :steps="rule" caption="How a pattern moves into Kre" />

That is why the shape of a Kre app is NestJS, but `[@@transactional]` has no self-invocation trap, a missing provider never reaches production, and a live page cannot silently miss an update.

## NestJS: the shape

NestJS gave Kre its vocabulary: controllers, providers, guards, pipes, interceptors, DTOs, gateways. In TypeScript these live on classes and decorators; in Kre they are attributes on ordinary functions, and the module system does the rest.

<Compare :rows="nest" left="NestJS" right="Kre" />

The big difference is the container. Nest builds the dependency graph when the app boots; Kre builds it when the app compiles. See [Dependency injection](/guide/dependency-injection) and [Controllers](/guide/controllers).

## Spring: the enterprise batteries

Spring contributes the features that Nest lacks or leaves to third-party packages: declarative transactions, method security, Actuator, profiles, Problem Details. In Spring all of these are runtime proxies; in Kre they are compile-time rewrites.

<Compare :rows="spring" left="Spring" right="Kre" />

::: tip The self-invocation trap is gone
In Spring, a `@Transactional` method called from another method of the same bean runs without a transaction, because the call never passes through the proxy. Kre has no proxy: `[@@transactional]` wraps the handler in `Db.within`, and every service that calls `Db.with_conn` inside it joins the same connection. See [Transactions](/data/transactions).
:::

## Rails: conventions for data

Rails gave the data layer its conveniences: finders, timestamps, `lock_version`, scaffolding, mailers with previews, background jobs and tasks. Rails implements them on ActiveRecord at runtime; Kre prints them from the table description and lets sqlgg check the SQL.

<Compare :rows="rails" left="Rails" right="Kre" />

## Symfony: mapping and tooling

Symfony's attribute-driven controllers inspired entity and query mapping, and its tooling inspired the profiler and the workflow component.

<Compare :rows="symfony" left="Symfony" right="Kre" />

## IHP: live data and jobs as tables

IHP is strongest where Nest and Spring are empty: pages that refresh themselves and jobs stored in the database you already have. Kre takes both, and makes live loaders stricter: the tables a route reads are declared next to the handler and checked by the test suite.

<Compare :rows="ihp" left="IHP" right="Kre" />

::: info One idea we reversed
IHP keeps `Schema.sql` as the source of truth and generates types from it. Kre goes the other way: the OCaml record is the truth, because that is where refined types and DTO rules live. The schema and the migrations are printed from it, and `dune test` fails when they drift. See [Migrations](/data/migrations).
:::

## Every pattern at a glance

| Pattern | From | Kre | Read more |
| --- | --- | --- | --- |
| Controllers and route decorators | NestJS, Spring | `[@@@controller]`, `[@@get]`, `[@@post]`, `[@@status]` | [Controllers](/guide/controllers) |
| Modules, providers, injection | NestJS, Spring | `[%wire]`, functors, `[@@@primary]`, `[@@@fallback]` | [Dependency injection](/guide/dependency-injection) |
| Lifecycle hooks | NestJS, Spring | `on_start`, `on_shutdown` in a provider | [Dependency injection](/guide/dependency-injection) |
| Validation pipes, Bean Validation | NestJS, Spring | `[@@deriving dto]`, `Refined`, `[@validate]` | [Validation & types](/guide/validation) |
| Query DTOs | NestJS, Symfony, Spring | `[@@deriving search, dto]`, `[@search]` | [Validation & types](/guide/validation) |
| Guards and roles | NestJS, Spring Security | `Guard.check` into evidence types, `Kre.Jwt.bearer` | [Guards & auth](/guide/guards-auth) |
| `@PreAuthorize` | Spring | `[@@authorize fun ~user ~cat -> ...]` | [Guards & auth](/guide/guards-auth) |
| Entity parameters | Symfony, Spring, Rails | `[@load Cats.find]` | [Controllers](/guide/controllers) |
| Exception filters, Problem Details | NestJS, Spring | `error_handler`, RFC 9457 | [Errors & interceptors](/guide/errors) |
| Interceptors | NestJS, Spring | `[@@intercept]` | [Errors & interceptors](/guide/errors) |
| Retries | Spring, Symfony | `[@@retry]`, `[@@backoff]` | [Errors & interceptors](/guide/errors) |
| ETags | Rails, Spring, Symfony | `[@@etag]` | [Controllers](/guide/controllers) |
| Repositories, derived finders | Spring Data, Rails, Doctrine | `[@@deriving table]`, `Table.crud`, sqlgg | [Tables & SQL](/data/database) |
| Paging | Spring, kaminari, Pagerfanta | `Kre_shared.Page` | [Tables & SQL](/data/database) |
| Timestamps, optimistic locking | Rails, JPA, Doctrine | `[@created_at]`, `[@updated_at]`, `[@version]` | [Tables & SQL](/data/database) |
| `@Transactional` | Spring | `[@@transactional]` | [Transactions](/data/transactions) |
| Migrations | Flyway, Rails | `kre migrate`, schema diff in `dune test` | [Migrations](/data/migrations) |
| Auto Refresh | IHP | `[@@live]`, `Router.child ~live` | [Live loaders](/data/live) |
| State machines | Symfony, AASM, Spring Statemachine | `[@@deriving workflow]` | [Workflows](/data/workflow) |
| Background jobs | IHP, Rails, Symfony, BullMQ | `Kre.Job`, `[@@job q]` | [Background jobs](/background/jobs) |
| Commands and scripts | Symfony, Rails, IHP, Spring | `[@@command]` | [Commands](/background/commands) |
| Events and schedules | NestJS, Spring | `Kre.Events`, `[@@on_event]`, `[@@cron]` | [Schedules & events](/background/schedule-events) |
| Mailers with previews | Rails, Symfony, IHP | `Kre.Mail`, `Outbox ()`, `/__kre/mail` | [Mail](/background/mail) |
| Generated clients | NestJS ecosystem | `kre client`, typed router | [Typed client & router](/client/client-router) |
| Typed views | IHP | Melange pages in `.mlx` with typed loaders | [Pages in mlx](/client/pages) |
| Declarative HTTP clients | Spring, NestJS, Symfony | `[%http_client]` | [Calling other APIs](/client/http-client) |
| Testing modules | NestJS, Spring, Rails, Symfony | `Kre_testing.use`, `Dream.test` | [Testing](/tooling/testing) |
| Actuator and bean graph | Spring, Nest Devtools | `Kre.Actuator`, `app.beans` | [Actuator & profiler](/tooling/observability) |
| Profiler | Symfony, Rails Bullet | `Kre.Profiler` | [Actuator & profiler](/tooling/observability) |
| Profiles | Spring | `Kre.Config.profile ()`, `KRE_ENV` | [CLI & OpenAPI](/tooling/cli) |
| Scaffolding | Rails, NestJS, Symfony | `kre new`, `kre generate controller` | [CLI & OpenAPI](/tooling/cli) |
| OpenAPI | NestJS, springdoc | `kre openapi`, `[@@summary]` | [CLI & OpenAPI](/tooling/cli) |

## What we deliberately did not take

Some famous features did not make the cut. Each one either exists to work around something OCaml already has, or hides a side effect that Kre prefers to keep visible in the code.

<Compare :rows="notTaken" left="The original" right="What Kre does instead" />

### Runtime containers

Nest's `@Module` and Spring's `ApplicationContext` resolve dependencies when the process starts. That is how a missing provider becomes a crash in staging. In Kre a provider is a module, a dependency is a functor parameter, and `main.ml` is the composition root. `[%wire]` resolves everything during the build and reports a missing provider, two candidates for one interface, or a cycle with a source location.

### AOP proxies

Spring's transactions, security and caching are proxies around beans. They are powerful, but they fail quietly: a call from inside the bean skips the proxy. Kre's attributes are rewritten into the handler's own code by `kre-ppx`, so there is nothing to bypass.

### ActiveRecord callbacks and Doctrine lifecycle events

`after_save` and `prePersist` run code you cannot see where the save happens. Kre keeps the effect explicit: write it in the service function, or publish an event on a typed `Kre.Events` topic. The shelter's congratulation letter is a job enqueued in the service, inside the same transaction — see [Background jobs](/background/jobs).

### Symfony Flex recipes and Spring Boot autoconfiguration

Installing a package should not change your application. In Kre every provider is a file `[%wire]` found in your project, and `/actuator/beans` lists exactly what was applied.

### Rails concerns and Symfony bundles

These package shared behaviour for classes and apps. OCaml already has modules, functors and dune libraries for that, so there is no extra concept.

### HATEOAS

Links in every response help clients that discover an API at runtime. A Kre client is generated from the server's spec and the page router is typed, so the client already knows every route at compile time.

### Circular dependencies, `forwardRef`, `ModuleRef`

These are Nest's escape hatches for TypeScript's lack of a module system. In OCaml, functors are applied in order and a cycle is a build error, so `forwardRef` has nothing to fix. Everything a controller needs is passed to it, so there is no token to look up with `ModuleRef` or discovery. Lazy modules are just `Lazy.t` or a function, and Kre does not hide Dream: `Dream.request` and `Dream.middleware` are part of the API.

::: tip See it all in one app
[The shelter tour](/reference/shelter) shows most of these patterns working together: `[@load]` with `[@@authorize]`, `[@@transactional]` with a rollback, live loaders, a job, a mailer and two commands.
:::

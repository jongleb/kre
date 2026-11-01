# What Kre has and what is in progress

✅ done and covered by tests · 🔜 next (phase 2) · ⏳ later (phase 3) · — not needed in OCaml

The whole application (users, cats, adoptions; everything from the tables below together) is `examples/shelter`.

Everything below is modules, functors, functions and ppx attributes; there are no classes, no reflection and no runtime container. DI and routing errors are compile errors.

## Application and DI

| Nest | Spring | Kre | Status | Example |
| --- | --- | --- | --- | --- |
| `@Module`, `imports`/`providers` | `@ComponentScan`, `@SpringBootApplication` | `[%wire]` scans the application directory at build time | ✅ | `examples/cats/bin/main.ml` |
| `@Injectable` | `@Service`, `@Component`, `@Repository` | a module with `Make` or `module type S` is a provider by itself | ✅ | `examples/cats/server/cats_service.ml` |
| constructor injection | `@Autowired` | functor parameters `Make (Db : Kre.Db.S)` | ✅ | `examples/cats/db/cats_db_service.ml` |
| `{ provide, useClass }` | `@Primary`, `@Qualifier` | `[@@@primary]`; functor parameter name = provider name | ✅ | `test/wire/wire.t` |
| `onModuleInit`, `onApplicationShutdown` | `@PostConstruct`, `@PreDestroy` | `let on_start` / `let on_shutdown` in the provider | ✅ | `examples/cats/db/database.ml` |
| `Scope.TRANSIENT` | `@Scope("prototype")` | `Make ()`: a new instance per application | ✅ | `Cats_service.Make ()` |
| `Scope.REQUEST` | `@RequestScope` | `Dream.field` + `[@guard]` | ✅ | `docs/examples/request_id.ml` |
| `forRoot(config)` | `@Configuration` + `@Bean` | a functor with a config module | ✅ | `Kre.Db.Make (Driver) (Config)` |
| `ConfigModule` | `@ConfigurationProperties`, `@Value` | `[@@deriving config]` | ✅ | `examples/cats/server/config.ml` |
| — | `@Profile` | `Kre.Config.profile ()` (`config/$KRE_ENV.env`) | ✅ | `docs/configuration.md` |
| `@Optional` provider | `@ConditionalOnMissingBean`, `required=false` | `[@@@fallback]`: a fallback provider used when there is no other | ✅ | |
| — | `@Lazy`, `@Conditional` | | ⏳ | |
| `@nestjs-modules/mailer` | Spring Mail; Rails ActionMailer, Symfony Mailer | `Kre.Mail`: `Smtp`, `Outbox` with a preview at `/__kre/mail` | ✅ | `docs/mail.md` |
| `@nestjs/bullmq` | `@Async`; Rails ActiveJob, Symfony Messenger, IHP Jobs | `Kre.Job` + `[@@job q]`: a queue in the same DB, `SKIP LOCKED`, retries, enqueue inside a transaction | ✅ | `docs/jobs.md` |
| `nest-commander` | `CommandLineRunner`; Symfony `#[AsCommand]`, Rails rake | `[@@command "…"]` + `app.commands` → `main.exe seed --count 3` | ✅ | `docs/commands.md` |
| Devtools | Symfony Web Profiler, Rails Bullet | `Kre.Profiler`: requests with their SQL and an N+1 marker, `/__kre/profiler`, dev only | ✅ | `docs/profiler.md` |
| — | — | `[%asset "logo.svg"]`, `[%icon "cat"]`: the file is checked at build time, hashed URL, `Kre.Assets.middleware` | ✅ | `examples/shelter/client/pages.mlx` |
| Devtools graph | `/actuator/beans` | `app.beans` from `[%wire]` → `/actuator/beans`, `/actuator/beans.mmd` | ✅ | `docs/actuator.md` |
| circular deps, `forwardRef`, `ModuleRef`, discovery | `ApplicationContext` | compile error / not needed | — | `docs/not-needed.md` |

## Controllers

| Nest | Spring | Kre | Status |
| --- | --- | --- | --- |
| `@Controller('cats')` | `@RestController`, `@RequestMapping` | `[@@@controller "cats"]` | ✅ |
| `@Get` `@Post` `@Put` `@Patch` `@Delete` | `@GetMapping` … | `[@@get ":id"]` … | ✅ |
| `@Head` `@Options` `@All` | `@RequestMapping(method=…)` | `[@@head]` `[@@options]` `[@@all]`; HEAD → GET without a body | ✅ |
| `@Get('files/*')` | `/**` | `[@@get "*"]` + `[@wildcard]`; exact routes win over the wildcard | ✅ |
| `@Controller({ host })`, `@HostParam` | — | `[@@@host ":account.example.com"]`, `[@host_param "account"]` | ✅ |
| `@HttpCode` | `@ResponseStatus` | `[@@status 201]` | ✅ |
| `@Header` | `ResponseEntity.header` | `[@@header (k, v)]` | ✅ |
| `@Redirect` | `redirect:` | `[@@redirect "/x"]`; dynamic: return `Dream.redirect` | ✅ |
| `@Sse` | `SseEmitter` | `T.t Lwt_stream.t Lwt.t` + `[@@sse]` | ✅ |
| `@Version` | — | `[@@@version 2]` (on the controller) | ✅ |
| `@Version` on a method | | `[@@version 2]` on the handler | ✅ |
| `@Render` (MVC) | `@Controller` + view | | ⏳ |

## Parameters

| Nest | Spring | Kre | Status |
| --- | --- | --- | --- |
| `@Param('id')` | `@PathVariable` | `~(id : Cat.Id.t)` with `:id`; `[@param "id"]` | ✅ |
| `@Query('page')`, `@Query()` | `@RequestParam` | `~(page : int)`, `?(limit : int = 20)`, `[@query "page-size"]`, `[@query]` | ✅ |
| — | `DomainClassConverter`; Symfony `#[MapEntity]`, Rails `set_cat` | `~(cat : (Cat.t[@load Cats.find]))`: id from the path → record or 404 | ✅ |
| `@Query() dto` | `@ModelAttribute`; Symfony `#[MapQueryString]` | `~(search : (Cat_search.t[@search]))`: one record on the server, in the client and in the page URL | ✅ |
| `@Body()`, `@Body('name')` | `@RequestBody` | `~(body : T.t)`, `[@body]`, `[@body "name"]` | ✅ |
| `@Headers('x')`, `@Headers()` | `@RequestHeader` | `[@header "X-Client-Name"]`, `[@headers]` | ✅ |
| `@Cookies`, `@SignedCookies` | `@CookieValue` | `[@cookie "x"]`, `[@signed_cookie "x"]`, `[@cookies]` | ✅ |
| `@Session()` | `@SessionAttribute` | `[@session "user_id"]` | ✅ |
| `@Ip()`, `@Req()` | `HttpServletRequest` | `[@ip]`, `(req : Dream.request)`, `[@req]` | ✅ |
| `createParamDecorator` | `HandlerMethodArgumentResolver` | `[@from guard]` | ✅ |
| `@UploadedFile`, `@UploadedFiles`, form fields | `@RequestPart`, `MultipartFile` | `[@file "avatar"] : Kre.Upload.t`, `[@files "photos"]`, `[@form "title"]` (the type decides the parsing) | ✅ |
| `@Res`, `@Next` | `HttpServletResponse` | the response is the return value | — |

## Request pipeline

| Nest | Spring | Kre | Status |
| --- | --- | --- | --- |
| middleware | `Filter` | `Dream.middleware`; `[@@@use]`, `[@@use]` | ✅ |
| `@UseGuards`, `CanActivate` | Spring Security | `[@@guards]`, `[@guard g]`, roles: `Guard.check` into an evidence type | ✅ |
| — | `@PreAuthorize` | `[@@authorize fun ~user ~id -> …]` | ✅ |
| `@UseInterceptors` | `HandlerInterceptor`, AOP `@Around` | `[@@intercept]`: `logging`, `timeout`, `map_error`, `tap` | ✅ |
| pipes, `ParseIntPipe` | converters | the parameter type (`Kre_shared.Scalar`, `Refined`, `Id`) | ✅ |
| `ValidationPipe` | `@Valid` | `[@@deriving dto]`: parsing = validation, 422 with paths | ✅ |
| exception filters, `@Catch` | `@ControllerAdvice`, `@ExceptionHandler` | `error_handler`, `[@@@error_handler]`, Problem Details (RFC 9457) | ✅ |
| `@UseFilters` on a method | `@ExceptionHandler` in the controller | `[@@error_handler h]` on the handler (wins over the controller and global ones) | ✅ |
| `dataSource.transaction`, `@nestjs-cls/transactional` | `@Transactional` | `[@@transactional]`; `Db.with_conn` inside joins the transaction | ✅ |
| `@nestjs/throttler` | — | `Kre.Rate_limit` | ✅ |
| helmet, `enableCors` | `@CrossOrigin` | `Kre.Secure_headers`, `Kre.Cors` | ✅ |
| Passport, JWT | Spring Security | `Kre.Jwt.bearer`, `Guard.session` | ✅ |
| — | `ShallowEtagHeaderFilter`, Rails `fresh_when` | `[@@etag]`, `Kre.Etag.middleware` → 304 | ✅ |
| — | Spring Retry `@Retryable` | `[@@retry 3] [@@backoff 0.1]` on any function | ✅ |
| `HttpModule` | `@HttpExchange`; Symfony HttpClient | `[%http_client: val user : login:string -> User.t [@@get "/users/:login"]]` → a functor over the base URL | ✅ |
| `Test.createTestingModule` + supertest | MockMvc | `Kre_testing.use` + the generated client, no socket | ✅ |

## Data and serialization

| Nest | Spring | Kre | Status |
| --- | --- | --- | --- |
| class-validator | Bean Validation | `Refined`, `[@validate]`, `~strict` | ✅ |
| entity id | `@Id` | `Kre_shared.Id.Make ()`: a distinct id type per entity | ✅ |
| — | Spring Statemachine; Symfony Workflow, Rails AASM | `[@@deriving workflow]` + `[@@transitions { pay = (function Cart -> Paid) }]`: `apply`, `allowed`, `sources`, mermaid | ✅ |
| TS `enum`, `@IsEnum` | `@Enumerated(STRING)` | a variant without arguments + `[@@deriving dto]`: a string in JSON, paths, query and the column | ✅ |
| TypeORM entity | `@Entity` | `[@@deriving table]` → DDL, `of_row` | ✅ |
| timestamps, `lock_version` | `@CreatedDate`, `@LastModifiedDate`, `@Version` | `[@created_at]`, `[@updated_at]`, `[@version]` in `table` + `Kre_shared.Time`; stale version → 409 | ✅ |
| pagination | `Pageable`, `Page<T>`; Rails kaminari | `Kre_shared.Page`: `Request.t` via `[@search]`, `'a t` with `total`, `page` and `count` in `Table.crud` | ✅ |
| repository `findOneBy` | Spring Data `findByStatus`, Rails `find_by` | `Table.crud` → `by_<col>` for `[@unique]`/`[@index]`/`[@references]`, `count` | ✅ |
| repositories | Spring Data | sqlgg: SQL is checked against the schema at build time | ✅ |
| migrations | Flyway | `kre migrate up/down/status/new` | ✅ |
| `@Exclude`, `@Expose`, `@Transform` | `@JsonIgnore`, `@JsonProperty` | `[@exclude]` (writeOnly), `[@key]`, `[@transform f]`; groups are `~pick_of` projections | ✅ |
| `PartialType`, `PickType`, `OmitType` | — | `[@@deriving dto ~partial_of / ~pick_of / ~omit_of]` + `summary_of_t`, `update_apply` | ✅ |
| CRUD repository | `JpaRepository` | `Kre.Table.crud` → sqlgg module `all`/`insert`/`find`/`update`/`delete`; `for_insert`/`for_update` from `[@@deriving table]` | ✅ |
| TypeORM `postgres` | Spring Data + PostgreSQL | `kre-db-postgresql` (libpq): sqlgg `-dialect postgresql`, `Table.schema Postgresql`, `insert_id` via `lastval()` | ✅ |

## Everything else

| Nest | Spring | Kre | Status |
| --- | --- | --- | --- |
| Swagger, `@ApiOperation` | springdoc, `@Operation` | `--emit-openapi`, `kre openapi` (3.1, validated); `[@@summary]`, `[@@description]` | ✅ |
| — | — | typed client `kre client` (Melange + native) | ✅ |
| — | — | typed page router, `[%path]`, `params`, `search` | ✅ |
| `nest new`, `nest g resource` | Spring Initializr; `rails g scaffold`, `make:crud` | `kre new`, `kre generate controller dogs name:string age:int born:time` | ✅ |
| `@OnEvent`, EventEmitter | `@EventListener` | `Kre.Events` (a topic typed by its event), `[@@on_event]`, subscription via `[%wire]` | ✅ |
| `@Cron`, `@Interval`, `@Timeout` | `@Scheduled` | `[@@cron]` (checked at build time), `[@@interval]`, `[@@after]` | ✅ |
| `CacheInterceptor`, `@CacheKey` | `@Cacheable`, `@CacheEvict` | `[@@cache ttl]` on GET; `Kre.Cache.memoize` → `{ find; evict; clear }` | ✅ |
| Terminus | Actuator | `Kre.Actuator`: health (`[@@health]` via `[%wire]`), info, env (secrets hidden), routes, openapi, Prometheus metrics | ✅ |
| `@WebSocketGateway`, `@SubscribeMessage`, `@MessageBody`, `@ConnectedSocket` | `@MessageMapping` | `[@@@gateway "chat"]`, `[@@subscribe "say"]`, `~(body : T.t)`, `(socket : Kre.Gateway.socket)`, `broadcast` | ✅ |
| — | — | live loaders (IHP Auto Refresh): `[@@live ["cats"]]`, publishing from the driver after commit, `/__kre/live`, `Router.child ~live`, list check with `KRE_ENV=test` | ✅ |
| queues, microservices, GraphQL | `@Async`, Spring Cloud | | ⏳ |

The whole application on one screen is `examples/showcase`: a server with all the example controllers; its route table is `examples/showcase/routes.t`.

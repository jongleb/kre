# Что есть в Kre и что делается

✅ сделано и проверено тестами · 🔜 следующее (фаза 2) · ⏳ позже (фаза 3) · — не нужно в OCaml

Приложение целиком (пользователи, коты, усыновления; всё из таблиц ниже вместе) — `examples/shelter`.

Всё ниже — модули, функторы, функции и атрибуты ppx; классов, рефлексии и рантайм-контейнера нет. Ошибки DI и маршрутов — ошибки компиляции.

## Приложение и DI

| Nest | Spring | Kre | Статус | Пример |
| --- | --- | --- | --- | --- |
| `@Module`, `imports`/`providers` | `@ComponentScan`, `@SpringBootApplication` | `[%wire]` сканирует каталог приложения при сборке | ✅ | `examples/cats/bin/main.ml` |
| `@Injectable` | `@Service`, `@Component`, `@Repository` | модуль с `Make` или `module type S` — провайдер сам | ✅ | `examples/cats/server/cats_service.ml` |
| constructor injection | `@Autowired` | параметры функтора `Make (Db : Kre.Db.S)` | ✅ | `examples/cats/db/cats_db_service.ml` |
| `{ provide, useClass }` | `@Primary`, `@Qualifier` | `[@@@primary]`; имя параметра функтора = имя провайдера | ✅ | `test/wire/wire.t` |
| `onModuleInit`, `onApplicationShutdown` | `@PostConstruct`, `@PreDestroy` | `let on_start` / `let on_shutdown` в провайдере | ✅ | `examples/cats/db/database.ml` |
| `Scope.TRANSIENT` | `@Scope("prototype")` | `Make ()` — новый экземпляр на применение | ✅ | `Cats_service.Make ()` |
| `Scope.REQUEST` | `@RequestScope` | `Dream.field` + `[@guard]` | ✅ | `docs/examples/request_id.ml` |
| `forRoot(config)` | `@Configuration` + `@Bean` | функтор с модулем-конфигом | ✅ | `Kre.Db.Make (Driver) (Config)` |
| `ConfigModule` | `@ConfigurationProperties`, `@Value` | `[@@deriving config]` | ✅ | `examples/cats/server/config.ml` |
| — | `@Profile` | `Kre.Config.profile ()` (`config/$KRE_ENV.env`) | ✅ | `docs/configuration.md` |
| `@Optional` provider | `@ConditionalOnMissingBean`, `required=false` | `[@@@fallback]` — запасной провайдер, если другого нет | ✅ | |
| — | `@Lazy`, `@Conditional` | | ⏳ | |
| `@nestjs-modules/mailer` | Spring Mail; Rails ActionMailer, Symfony Mailer | `Kre.Mail`: `Smtp`, `Outbox` с превью `/__kre/mail` | ✅ | `docs/mail.md` |
| `@nestjs/bullmq` | `@Async`; Rails ActiveJob, Symfony Messenger, IHP Jobs | `Kre.Job` + `[@@job q]`: очередь в той же БД, `SKIP LOCKED`, повторы, enqueue в транзакции | ✅ | `docs/jobs.md` |
| `nest-commander` | `CommandLineRunner`; Symfony `#[AsCommand]`, Rails rake | `[@@command "…"]` + `app.commands` → `main.exe seed --count 3` | ✅ | `docs/commands.md` |
| Devtools | Symfony Web Profiler, Rails Bullet | `Kre.Profiler`: запросы с их SQL и пометкой N+1, `/__kre/profiler`, только в dev | ✅ | `docs/profiler.md` |
| — | — | `[%asset "logo.svg"]`, `[%icon "cat"]`: файл проверяется при сборке, адрес с хешем, `Kre.Assets.middleware` | ✅ | `examples/shelter/client/pages.mlx` |
| Devtools graph | `/actuator/beans` | `app.beans` из `[%wire]` → `/actuator/beans`, `/actuator/beans.mmd` | ✅ | `docs/actuator.md` |
| circular deps, `forwardRef`, `ModuleRef`, discovery | `ApplicationContext` | ошибка компиляции / не нужно | — | `docs/not-needed.md` |

## Контроллеры

| Nest | Spring | Kre | Статус |
| --- | --- | --- | --- |
| `@Controller('cats')` | `@RestController`, `@RequestMapping` | `[@@@controller "cats"]` | ✅ |
| `@Get` `@Post` `@Put` `@Patch` `@Delete` | `@GetMapping` … | `[@@get ":id"]` … | ✅ |
| `@Head` `@Options` `@All` | `@RequestMapping(method=…)` | `[@@head]` `[@@options]` `[@@all]`; HEAD → GET без тела | ✅ |
| `@Get('files/*')` | `/**` | `[@@get "*"]` + `[@wildcard]`; точные маршруты важнее маски | ✅ |
| `@Controller({ host })`, `@HostParam` | — | `[@@@host ":account.example.com"]`, `[@host_param "account"]` | ✅ |
| `@HttpCode` | `@ResponseStatus` | `[@@status 201]` | ✅ |
| `@Header` | `ResponseEntity.header` | `[@@header (k, v)]` | ✅ |
| `@Redirect` | `redirect:` | `[@@redirect "/x"]`; динамический — вернуть `Dream.redirect` | ✅ |
| `@Sse` | `SseEmitter` | `T.t Lwt_stream.t Lwt.t` + `[@@sse]` | ✅ |
| `@Version` | — | `[@@@version 2]` (на контроллер) | ✅ |
| `@Version` на метод | | `[@@version 2]` на хендлере | ✅ |
| `@Render` (MVC) | `@Controller` + view | | ⏳ |

## Параметры

| Nest | Spring | Kre | Статус |
| --- | --- | --- | --- |
| `@Param('id')` | `@PathVariable` | `~(id : Cat.Id.t)` при `:id`; `[@param "id"]` | ✅ |
| `@Query('page')`, `@Query()` | `@RequestParam` | `~(page : int)`, `?(limit : int = 20)`, `[@query "page-size"]`, `[@query]` | ✅ |
| — | `DomainClassConverter`; Symfony `#[MapEntity]`, Rails `set_cat` | `~(cat : (Cat.t[@load Cats.find]))`: id из пути → запись или 404 | ✅ |
| `@Query() dto` | `@ModelAttribute`; Symfony `#[MapQueryString]` | `~(search : (Cat_search.t[@search]))` — одна запись на сервере, в клиенте и в URL страницы | ✅ |
| `@Body()`, `@Body('name')` | `@RequestBody` | `~(body : T.t)`, `[@body]`, `[@body "name"]` | ✅ |
| `@Headers('x')`, `@Headers()` | `@RequestHeader` | `[@header "X-Client-Name"]`, `[@headers]` | ✅ |
| `@Cookies`, `@SignedCookies` | `@CookieValue` | `[@cookie "x"]`, `[@signed_cookie "x"]`, `[@cookies]` | ✅ |
| `@Session()` | `@SessionAttribute` | `[@session "user_id"]` | ✅ |
| `@Ip()`, `@Req()` | `HttpServletRequest` | `[@ip]`, `(req : Dream.request)`, `[@req]` | ✅ |
| `createParamDecorator` | `HandlerMethodArgumentResolver` | `[@from guard]` | ✅ |
| `@UploadedFile`, `@UploadedFiles`, form fields | `@RequestPart`, `MultipartFile` | `[@file "avatar"] : Kre.Upload.t`, `[@files "photos"]`, `[@form "title"]` (тип решает разбор) | ✅ |
| `@Res`, `@Next` | `HttpServletResponse` | ответ — возвращаемое значение | — |

## Конвейер запроса

| Nest | Spring | Kre | Статус |
| --- | --- | --- | --- |
| middleware | `Filter` | `Dream.middleware`; `[@@@use]`, `[@@use]` | ✅ |
| `@UseGuards`, `CanActivate` | Spring Security | `[@@guards]`, `[@guard g]`, роли — `Guard.check` в тип-доказательство | ✅ |
| — | `@PreAuthorize` | `[@@authorize fun ~user ~id -> …]` | ✅ |
| `@UseInterceptors` | `HandlerInterceptor`, AOP `@Around` | `[@@intercept]`: `logging`, `timeout`, `map_error`, `tap` | ✅ |
| pipes, `ParseIntPipe` | converters | тип параметра (`Kre_shared.Scalar`, `Refined`, `Id`) | ✅ |
| `ValidationPipe` | `@Valid` | `[@@deriving dto]`: разбор = проверка, 422 с путями | ✅ |
| exception filters, `@Catch` | `@ControllerAdvice`, `@ExceptionHandler` | `error_handler`, `[@@@error_handler]`, Problem Details (RFC 9457) | ✅ |
| `@UseFilters` на метод | `@ExceptionHandler` в контроллере | `[@@error_handler h]` на хендлере (важнее контроллерного и глобального) | ✅ |
| `dataSource.transaction`, `@nestjs-cls/transactional` | `@Transactional` | `[@@transactional]`; `Db.with_conn` внутри присоединяется к транзакции | ✅ |
| `@nestjs/throttler` | — | `Kre.Rate_limit` | ✅ |
| helmet, `enableCors` | `@CrossOrigin` | `Kre.Secure_headers`, `Kre.Cors` | ✅ |
| Passport, JWT | Spring Security | `Kre.Jwt.bearer`, `Guard.session` | ✅ |
| — | `ShallowEtagHeaderFilter`, Rails `fresh_when` | `[@@etag]`, `Kre.Etag.middleware` → 304 | ✅ |
| — | Spring Retry `@Retryable` | `[@@retry 3] [@@backoff 0.1]` на любой функции | ✅ |
| `HttpModule` | `@HttpExchange`; Symfony HttpClient | `[%http_client: val user : login:string -> User.t [@@get "/users/:login"]]` → функтор над адресом | ✅ |
| `Test.createTestingModule` + supertest | MockMvc | `Kre_testing.use` + сгенерированный клиент, без сокета | ✅ |

## Данные и сериализация

| Nest | Spring | Kre | Статус |
| --- | --- | --- | --- |
| class-validator | Bean Validation | `Refined`, `[@validate]`, `~strict` | ✅ |
| entity id | `@Id` | `Kre_shared.Id.Make ()` — свой тип id на сущность | ✅ |
| — | Spring Statemachine; Symfony Workflow, Rails AASM | `[@@deriving workflow]` + `[@@transitions { pay = (function Cart -> Paid) }]`: `apply`, `allowed`, `sources`, mermaid | ✅ |
| TS `enum`, `@IsEnum` | `@Enumerated(STRING)` | вариант без аргументов + `[@@deriving dto]` — строка в JSON, пути, query и столбце | ✅ |
| TypeORM entity | `@Entity` | `[@@deriving table]` → DDL, `of_row` | ✅ |
| timestamps, `lock_version` | `@CreatedDate`, `@LastModifiedDate`, `@Version` | `[@created_at]`, `[@updated_at]`, `[@version]` в `table` + `Kre_shared.Time`; устаревшая версия → 409 | ✅ |
| пагинация | `Pageable`, `Page<T>`; Rails kaminari | `Kre_shared.Page`: `Request.t` через `[@search]`, `'a t` с `total`, `page` и `count` в `Table.crud` | ✅ |
| repository `findOneBy` | Spring Data `findByStatus`, Rails `find_by` | `Table.crud` → `by_<col>` по `[@unique]`/`[@index]`/`[@references]`, `count` | ✅ |
| repositories | Spring Data | sqlgg: SQL проверяется против схемы при сборке | ✅ |
| migrations | Flyway | `kre migrate up/down/status/new` | ✅ |
| `@Exclude`, `@Expose`, `@Transform` | `@JsonIgnore`, `@JsonProperty` | `[@exclude]` (writeOnly), `[@key]`, `[@transform f]`; группы — проекции `~pick_of` | ✅ |
| `PartialType`, `PickType`, `OmitType` | — | `[@@deriving dto ~partial_of / ~pick_of / ~omit_of]` + `summary_of_t`, `update_apply` | ✅ |
| CRUD repository | `JpaRepository` | `Kre.Table.crud` → sqlgg-модуль `all`/`insert`/`find`/`update`/`delete`; `for_insert`/`for_update` из `[@@deriving table]` | ✅ |
| TypeORM `postgres` | Spring Data + PostgreSQL | `kre-db-postgresql` (libpq): sqlgg `-dialect postgresql`, `Table.schema Postgresql`, `insert_id` через `lastval()` | ✅ |

## Остальное

| Nest | Spring | Kre | Статус |
| --- | --- | --- | --- |
| Swagger, `@ApiOperation` | springdoc, `@Operation` | `--emit-openapi`, `kre openapi` (3.1, валидируется); `[@@summary]`, `[@@description]` | ✅ |
| — | — | типизированный клиент `kre client` (Melange + native) | ✅ |
| — | — | типизированный роутер страниц, `[%path]`, `params`, `search` | ✅ |
| `nest new`, `nest g resource` | Spring Initializr; `rails g scaffold`, `make:crud` | `kre new`, `kre generate controller dogs name:string age:int born:time` | ✅ |
| `@OnEvent`, EventEmitter | `@EventListener` | `Kre.Events` (топик с типом события), `[@@on_event]`, подписка через `[%wire]` | ✅ |
| `@Cron`, `@Interval`, `@Timeout` | `@Scheduled` | `[@@cron]` (проверка при сборке), `[@@interval]`, `[@@after]` | ✅ |
| `CacheInterceptor`, `@CacheKey` | `@Cacheable`, `@CacheEvict` | `[@@cache ttl]` на GET; `Kre.Cache.memoize` → `{ find; evict; clear }` | ✅ |
| Terminus | Actuator | `Kre.Actuator`: health (`[@@health]` через `[%wire]`), info, env (секреты скрыты), routes, openapi, Prometheus metrics | ✅ |
| `@WebSocketGateway`, `@SubscribeMessage`, `@MessageBody`, `@ConnectedSocket` | `@MessageMapping` | `[@@@gateway "chat"]`, `[@@subscribe "say"]`, `~(body : T.t)`, `(socket : Kre.Gateway.socket)`, `broadcast` | ✅ |
| — | — | live loaders (IHP Auto Refresh): `[@@live ["cats"]]`, публикация из драйвера после commit, `/__kre/live`, `Router.child ~live`, проверка списка при `KRE_ENV=test` | ✅ |
| queues, microservices, GraphQL | `@Async`, Spring Cloud | | ⏳ |

Всё приложение на одном экране — `examples/showcase`: сервер со всеми контроллерами-примерами, его таблица маршрутов — `examples/showcase/routes.t`.

# Что есть в Forge и что делается

✅ сделано и проверено тестами · 🔜 следующее (фаза 2) · ⏳ позже (фаза 3) · — не нужно в OCaml

Всё ниже — модули, функторы, функции и атрибуты ppx; классов, рефлексии и рантайм-контейнера нет. Ошибки DI и маршрутов — ошибки компиляции.

## Приложение и DI

| Nest | Spring | Forge | Статус | Пример |
| --- | --- | --- | --- | --- |
| `@Module`, `imports`/`providers` | `@ComponentScan`, `@SpringBootApplication` | `[%wire]` сканирует каталог приложения при сборке | ✅ | `examples/cats/bin/main.ml` |
| `@Injectable` | `@Service`, `@Component`, `@Repository` | модуль с `Make` или `module type S` — провайдер сам | ✅ | `examples/cats/server/cats_service.ml` |
| constructor injection | `@Autowired` | параметры функтора `Make (Db : Forge.Db.S)` | ✅ | `examples/cats/db/cats_db_service.ml` |
| `{ provide, useClass }` | `@Primary`, `@Qualifier` | `[@@@primary]`; имя параметра функтора = имя провайдера | ✅ | `test/wire/wire.t` |
| `onModuleInit`, `onApplicationShutdown` | `@PostConstruct`, `@PreDestroy` | `let on_start` / `let on_shutdown` в провайдере | ✅ | `examples/cats/db/database.ml` |
| `Scope.TRANSIENT` | `@Scope("prototype")` | `Make ()` — новый экземпляр на применение | ✅ | `Cats_service.Make ()` |
| `Scope.REQUEST` | `@RequestScope` | `Dream.field` + `[@guard]` | ✅ | `docs/examples/request_id.ml` |
| `forRoot(config)` | `@Configuration` + `@Bean` | функтор с модулем-конфигом | ✅ | `Forge.Db.Make (Driver) (Config)` |
| `ConfigModule` | `@ConfigurationProperties`, `@Value` | `[@@deriving config]` | ✅ | `examples/cats/server/config.ml` |
| — | `@Profile` | `Forge.Config.profile ()` (`config/$FORGE_ENV.env`) | ✅ | `docs/configuration.md` |
| `@Optional` provider | `@ConditionalOnMissingBean`, `required=false` | `[@@@fallback]` — запасной провайдер, если другого нет | ✅ | |
| — | `@Lazy`, `@Conditional` | | ⏳ | |
| circular deps, `forwardRef`, `ModuleRef`, discovery | `ApplicationContext` | ошибка компиляции / не нужно | — | `docs/not-needed.md` |

## Контроллеры

| Nest | Spring | Forge | Статус |
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

| Nest | Spring | Forge | Статус |
| --- | --- | --- | --- |
| `@Param('id')` | `@PathVariable` | `~(id : Cat.Id.t)` при `:id`; `[@param "id"]` | ✅ |
| `@Query('page')`, `@Query()` | `@RequestParam` | `~(page : int)`, `?(limit : int = 20)`, `[@query "page-size"]`, `[@query]` | ✅ |
| `@Body()`, `@Body('name')` | `@RequestBody` | `~(body : T.t)`, `[@body]`, `[@body "name"]` | ✅ |
| `@Headers('x')`, `@Headers()` | `@RequestHeader` | `[@header "X-Client-Name"]`, `[@headers]` | ✅ |
| `@Cookies`, `@SignedCookies` | `@CookieValue` | `[@cookie "x"]`, `[@signed_cookie "x"]`, `[@cookies]` | ✅ |
| `@Session()` | `@SessionAttribute` | `[@session "user_id"]` | ✅ |
| `@Ip()`, `@Req()` | `HttpServletRequest` | `[@ip]`, `(req : Dream.request)`, `[@req]` | ✅ |
| `createParamDecorator` | `HandlerMethodArgumentResolver` | `[@from guard]` | ✅ |
| `@UploadedFile`, `@UploadedFiles`, form fields | `@RequestPart`, `MultipartFile` | `[@file "avatar"] : Forge.Upload.t`, `[@files "photos"]`, `[@form "title"]` (тип решает разбор) | ✅ |
| `@Res`, `@Next` | `HttpServletResponse` | ответ — возвращаемое значение | — |

## Конвейер запроса

| Nest | Spring | Forge | Статус |
| --- | --- | --- | --- |
| middleware | `Filter` | `Dream.middleware`; `[@@@use]`, `[@@use]` | ✅ |
| `@UseGuards`, `CanActivate` | Spring Security | `[@@guards]`, `[@guard g]`, роли — `Guard.check` в тип-доказательство | ✅ |
| — | `@PreAuthorize` | `[@@authorize fun ~user ~id -> …]` | ✅ |
| `@UseInterceptors` | `HandlerInterceptor`, AOP `@Around` | `[@@intercept]`: `logging`, `timeout`, `map_error`, `tap` | ✅ |
| pipes, `ParseIntPipe` | converters | тип параметра (`Forge_shared.Scalar`, `Refined`, `Id`) | ✅ |
| `ValidationPipe` | `@Valid` | `[@@deriving dto]`: разбор = проверка, 422 с путями | ✅ |
| exception filters, `@Catch` | `@ControllerAdvice`, `@ExceptionHandler` | `error_handler`, `[@@@error_handler]`, Problem Details (RFC 9457) | ✅ |
| `@UseFilters` на метод | `@ExceptionHandler` в контроллере | `[@@error_handler h]` на хендлере (важнее контроллерного и глобального) | ✅ |
| — | `@Transactional` | `[@@transactional]` + `[@from Db.tx]` | ✅ |
| `@nestjs/throttler` | — | `Forge.Rate_limit` | ✅ |
| helmet, `enableCors` | `@CrossOrigin` | `Forge.Secure_headers`, `Forge.Cors` | ✅ |
| Passport, JWT | Spring Security | `Forge.Jwt.bearer`, `Guard.session` | ✅ |

## Данные и сериализация

| Nest | Spring | Forge | Статус |
| --- | --- | --- | --- |
| class-validator | Bean Validation | `Refined`, `[@validate]`, `~strict` | ✅ |
| entity id | `@Id` | `Forge_shared.Id.Make ()` — свой тип id на сущность | ✅ |
| TypeORM entity | `@Entity` | `[@@deriving table]` → DDL, `of_row` | ✅ |
| repositories | Spring Data | sqlgg: SQL проверяется против схемы при сборке | ✅ |
| migrations | Flyway | `forge migrate up/down/status/new` | ✅ |
| `@Exclude`, `@Expose`, `@Transform` | `@JsonIgnore`, `@JsonProperty` | `[@exclude]` (writeOnly), `[@key]`, `[@transform f]`; группы — проекции `~pick_of` | ✅ |
| `PartialType`, `PickType`, `OmitType` | — | `[@@deriving dto ~partial_of / ~pick_of / ~omit_of]` + `summary_of_t`, `update_apply` | ✅ |
| CRUD repository | `JpaRepository` | `Forge.Table.crud` → sqlgg-модуль `all`/`insert`/`find`/`update`/`delete`; `for_insert`/`for_update` из `[@@deriving table]` | ✅ |
| Postgres | | `Forge_db_pgx` | 🔜 |

## Остальное

| Nest | Spring | Forge | Статус |
| --- | --- | --- | --- |
| Swagger, `@ApiOperation` | springdoc, `@Operation` | `--emit-openapi`, `forge openapi` (3.1, валидируется); `[@@summary]`, `[@@description]` | ✅ |
| — | — | типизированный клиент `forge client` (Melange + native) | ✅ |
| — | — | типизированный роутер страниц, `[%path]`, `params`, `search` | ✅ |
| `nest new`, `nest g resource` | Spring Initializr | `forge new`, `forge generate` | ✅ |
| `@OnEvent`, EventEmitter | `@EventListener` | `Forge.Events` (топик с типом события), `[@@on_event]`, подписка через `[%wire]` | ✅ |
| `@Cron`, `@Interval`, `@Timeout` | `@Scheduled` | `[@@cron]` (проверка при сборке), `[@@interval]`, `[@@after]` | ✅ |
| `CacheInterceptor`, `@CacheKey` | `@Cacheable`, `@CacheEvict` | `[@@cache ttl]` на GET; `Forge.Cache.memoize` → `{ find; evict; clear }` | ✅ |
| Terminus | Actuator | `Forge.Actuator`: health (`[@@health]` через `[%wire]`), info, env (секреты скрыты), routes, openapi, Prometheus metrics | ✅ |
| `@WebSocketGateway`, `@SubscribeMessage`, `@MessageBody`, `@ConnectedSocket` | `@MessageMapping` | `[@@@gateway "chat"]`, `[@@subscribe "say"]`, `~(body : T.t)`, `(socket : Forge.Gateway.socket)`, `broadcast` | ✅ |
| — | — | live loaders (IHP Auto Refresh): `[@@live ["cats"]]`, публикация из драйвера после commit, `/__forge/live`, `Router.child ~live`, проверка списка при `FORGE_ENV=test` | ✅ |
| queues, microservices, GraphQL | `@Async`, Spring Cloud | | ⏳ |

Всё приложение на одном экране — `examples/showcase`: сервер со всеми контроллерами-примерами, его таблица маршрутов — `examples/showcase/routes.t`.

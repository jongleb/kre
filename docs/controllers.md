# Controllers

Nest: класс с `@Controller('cats')` и методами `@Get()`, `@Get(':id')`, `@Post()`. Forge: файл с `[@@@controller "cats"]` и функциями с атрибутами `[@@get]`, `[@@get ":id"]`, `[@@post]`. Хендлер — обычная функция; ppx читает её параметры и тип результата и генерирует `Paths`, `spec` и `register`.

<!-- $MDX file=../examples/cats/server/cats_controller.ml -->
```ocaml
[@@@controller "cats"]
[@@@use [ Logger_middleware.use ]]

let find_all (module Cats : Cats_service.S) ?(limit : int = 20) () :
    Cat.t list Lwt.t =
  let%lwt all = Cats.find_all () in
  Lwt.return (List.filteri (fun i _ -> i < limit) all)
[@@get]

let find_one (module Cats : Cats_service.S) ~(id : Cat.Id.t) :
    (Cat.t, Forge.Error.t) result Lwt.t =
  let%lwt cat = Cats.find id in
  Lwt.return (Option.to_result cat ~none:(Forge.Error.not_found "cat"))
[@@get ":id"]

let create (module Cats : Cats_service.S) ~(user : (string[@guard Auth.user]))
    ~(body : Create_cat_dto.t) : Cat.t Lwt.t =
  Dream.log "%s adds a cat" user;
  Cats.add body
[@@post] [@@status 201]
```

- `~(id : int)` совпадает с `:id` в пути — **path**-параметр; не разобрался как `int` → 404.
- `?(limit : int = 20)` — **query** с дефолтом; `~(x : t)` — обязательный query, `~(x : t list)` — повторяемый.
- `~(body : Create_cat_dto.t)` — **тело**: JSON → `Create_cat_dto.of_json`; не JSON → 400, не прошёл разбор → 422.
- `~(user : string [@guard Auth.user])` — значение из запроса (guard), в `spec` и клиент не попадает.
- `(module Cats : Cats_service.S)` — **зависимость** (modular explicit): `register` принимает модуль и передаёт его хендлеру.
- Тип результата решает сериализацию: `T.t Lwt.t` → JSON, `T.t option Lwt.t` → JSON или 404, `(T.t, Forge.Error.t) result Lwt.t` → JSON или ошибка, `unit Lwt.t` → 204, `string Lwt.t` → текст.
- `T.t Lwt_stream.t Lwt.t` с `[@@sse]` — server-sent events (`@Sse`), см. `docs/examples/ticks_controller.ml`.
- `[@@status 201]` — код успеха (`@HttpCode`); `[@@header ("Cache-Control", "no-store")]` — `@Header`; `[@@redirect "/cats"]` — `@Redirect`; `[@@timeout 5.0]` — 504, если хендлер не успел; `[@@@error_handler h]` — фильтр исключений на весь контроллер.

Пути доступны и коду: `Routes.sprintf (Cats_controller.Paths.find_one ()) 42 = "/cats/42"`. Сгенерированный код целиком — `test/ppx/controller.t`.

## Декораторы параметров

Атрибут на типе параметра говорит, откуда взять значение; тип решает, как его разобрать и обязательно ли оно (`option` — нет, `list` — повторяемое).

| Nest | Spring | Forge |
| --- | --- | --- |
| `@Req()` | `HttpServletRequest` | `(req : Dream.request)` или `[@req]` |
| `@Param('id')` | `@PathVariable` | `~(id : int)` при `:id` в пути; другое имя — `[@param "id"]` |
| `@Query('page')`, `@Query()` | `@RequestParam` | `~(page : int)`; другое имя — `[@query "page-size"]`; все — `[@query]` |
| `@Body()`, `@Body('name')` | `@RequestBody` | `~(body : T.t)` или `[@body]` на любой метке; поле — `[@body "name"]` |
| `@Headers('x')`, `@Headers()` | `@RequestHeader` | `[@header "X-Client-Name"]`; все — `[@headers]` |
| `@Cookies('x')`, `@SignedCookies('x')` | `@CookieValue` | `[@cookie "theme"]`, `[@signed_cookie "sid"]`; все — `[@cookies]` |
| `@Session()` | `@SessionAttribute` | `[@session "user_id"]` |
| `@Ip()` | `request.getRemoteAddr()` | `[@ip]` |
| `@HostParam()` | — | `[@host]` |
| свой декоратор | `HandlerMethodArgumentResolver` | `[@from guard]` с любым `'a Forge.Guard.t` |
| `@Res()`, `@Next()` | `HttpServletResponse` | не нужны: ответ — возвращаемое значение, `next` — middleware |

<!-- $MDX file=examples/entities_controller.ml -->
```ocaml
[@@@controller "entities"]

let update ~(id : int) ~(entity : (Profile.t[@body]))
    ~(client_name : (string[@header "X-Client-Name"]))
    ~(trace : (string option[@header "X-Trace"]))
    ~(theme : (string option[@cookie "theme"]))
    ~(page_size : (int[@query "page-size"])) (ip : (string[@ip])) () :
    string Lwt.t =
  Lwt.return
    (String.concat " "
       [
         string_of_int id;
         entity.display_name;
         client_name;
         Option.value trace ~default:"-";
         Option.value theme ~default:"-";
         string_of_int page_size;
         ip;
       ])
[@@put ":id"]

let rename ~(cat_id : (int[@param "id"])) ~(name : (Cat.Name.t[@body "name"])) :
    string Lwt.t =
  Lwt.return (Printf.sprintf "%d is now %s" cat_id (Cat.Name.to_repr name))
[@@patch ":id"]
```

Заголовки и cookies попадают в `spec` и OpenAPI (`in: header`, `in: cookie`); заголовки — ещё и в сгенерированный клиент: `update ~id ~client_name ?trace ~page_size ~body`.

## Глаголы, маски, хосты

`[@@get]`, `[@@post]`, `[@@put]`, `[@@patch]`, `[@@delete]`, `[@@head]`, `[@@options]`, `[@@all]` (`@All` — маршрут на каждый метод). HEAD без своего маршрута отвечает GET-хендлером без тела. Маска `[@@get "*"]` — хвост пути в параметр `[@wildcard]`. `[@@@host ":account.example.com"]` — контроллер отвечает только на такие хосты (`@Controller({ host })`), `[@host_param "account"]` — часть хоста (`@HostParam`).

<!-- $MDX file=examples/files_controller.ml -->
```ocaml
[@@@controller "files"]

let download ~(path : (string[@wildcard])) () : string Lwt.t =
  Lwt.return ("file " ^ path)
[@@get "*"]

let probe () : unit Lwt.t = Lwt.return_unit [@@options "probe"]

let echo (request : Dream.request) () : string Lwt.t =
  Lwt.return (Dream.method_to_string (Dream.method_ request))
[@@all "echo"]
```

<!-- $MDX file=examples/tenant_controller.ml -->
```ocaml
[@@@controller "tenant"]
[@@@host ":account.example.com"]

let whoami ~(account : (string[@host_param "account"])) () : string Lwt.t =
  Lwt.return account
[@@get]
```

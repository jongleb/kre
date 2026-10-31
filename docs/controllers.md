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

let find_one (module Cats : Cats_service.S) ~(id : int) :
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

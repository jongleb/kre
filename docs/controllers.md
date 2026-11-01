# Controllers

Nest: a class with `@Controller('cats')` and methods `@Get()`, `@Get(':id')`, `@Post()`. Kre: a file with `[@@@controller "cats"]` and functions with the attributes `[@@get]`, `[@@get ":id"]`, `[@@post]`. A handler is a plain function; the ppx reads its parameters and result type and generates `Paths`, `spec` and `register`.

<!-- $MDX file=../examples/cats/server/cats_controller.ml -->
```ocaml
[@@@controller "cats"]
[@@@use [ Logger_middleware.use ]]

let find_all (module Cats : Cats_service.S) ~(search : (Cat_search.t[@search]))
    () : Cat.t list Lwt.t =
  let%lwt all = Cats.find_all () in
  Lwt.return
    (List.filteri
       (fun i _ -> i < search.limit)
       (List.filter
          (fun (cat : Cat.t) ->
            Option.fold ~none:true
              ~some:(fun breed ->
                String.equal (Cat.Breed.to_repr breed)
                  (Cat.Breed.to_repr cat.breed))
              search.breed)
          all))
[@@get] [@@summary "List cats"] [@@live [ "cats" ]]

let find_one (module Cats : Cats_service.S) ~(id : Cat.Id.t) :
    (Cat.t, Kre.Error.t) result Lwt.t =
  let%lwt cat = Cats.find id in
  Lwt.return (Option.to_result cat ~none:(Kre.Error.not_found "cat"))
[@@get ":id"]
[@@etag]
[@@summary "Find a cat"]
[@@description "Answers 404 when no cat has this id."]

let create (module Cats : Cats_service.S) ~(user : (string[@guard Auth.user]))
    ~(body : Create_cat_dto.t) : Cat.t Lwt.t =
  Dream.log "%s adds a cat" user;
  Cats.add body
[@@post] [@@status 201]
```

- `~(id : int)` matches `:id` in the path: a **path** parameter; if it does not parse as `int` → 404.
- `?(limit : int = 20)` is a **query** parameter with a default; `~(x : t)` is a required query parameter, `~(x : t list)` a repeatable one.
- `~(cat : (Cat.t[@load Cats.find]))` with `[@@get ":cat"]` is an **entity from the path**, like `#[MapEntity]` in Symfony, `DomainClassConverter` in Spring and `before_action :set_cat` in Rails. The segment is parsed as `Cat.Id.t` (type `M.t` → identifier `M.Id.t`); the function gets the id and returns `M.t option Lwt.t`; `None` → 404. The handler and `[@@authorize fun ~user ~cat -> …]` get the already loaded record; in the client and in OpenAPI it is a plain path parameter `~cat : Cat.Id.t` (`examples/shelter/server/cats_controller.ml`).
- `~(search : (Cat_search.t[@search]))` is the **whole query string** in one record, like `#[MapQueryString]` in Symfony, `@Query() dto` in Nest and `@ModelAttribute` in Spring. The record with `[@@deriving search, dto]` lives in shared: the same `Cat_search.codec` parses the page URL in the router (`~search:Cat_search.codec`), and the generated client takes `~search` of the same type. A parse error → 400 with field errors; in OpenAPI it is `style: form, explode: true` with the record schema.
- `~(body : Create_cat_dto.t)` is the **body**: JSON → `Create_cat_dto.of_json`; not JSON → 400, failed to parse → 422.
- `~(user : string [@guard Auth.user])` is a value from the request (a guard); it does not go into `spec` or the client.
- `(module Cats : Cats_service.S)` is a **dependency** (modular explicit): `register` takes the module and passes it to the handler.
- The result type decides serialization: `T.t Lwt.t` → JSON, `T.t option Lwt.t` → JSON or 404, `(T.t, Kre.Error.t) result Lwt.t` → JSON or an error, `unit Lwt.t` → 204, `string Lwt.t` → text.
- `T.t Lwt_stream.t Lwt.t` with `[@@sse]` is server-sent events (`@Sse`), see `docs/examples/ticks_controller.ml`.
- `[@@status 201]` is the success code (`@HttpCode`); `[@@header ("Cache-Control", "no-store")]` is `@Header`; `[@@redirect "/cats"]` is `@Redirect`; `[@@timeout 5.0]` gives 504 if the handler did not finish in time; `[@@@error_handler h]` is an exception filter for the whole controller, `[@@error_handler h]` for one handler; `[@@version 2]` on a handler is a version for that handler only.

Paths are available to code as well: `Routes.sprintf (Cats_controller.Paths.find_one ()) 42 = "/cats/42"`. The full generated code is in `test/ppx/controller.t`.

## Parameter decorators

An attribute on the parameter type says where to take the value from; the type decides how to parse it and whether it is required (`option`: no, `list`: repeatable).

| Nest | Spring | Kre |
| --- | --- | --- |
| `@Req()` | `HttpServletRequest` | `(req : Dream.request)` or `[@req]` |
| `@Param('id')` | `@PathVariable` | `~(id : int)` with `:id` in the path; another name: `[@param "id"]` |
| `@Query('page')`, `@Query()` | `@RequestParam` | `~(page : int)`; another name: `[@query "page-size"]`; all: `[@query]` |
| `@Body()`, `@Body('name')` | `@RequestBody` | `~(body : T.t)` or `[@body]` on any label; a field: `[@body "name"]` |
| `@Headers('x')`, `@Headers()` | `@RequestHeader` | `[@header "X-Client-Name"]`; all: `[@headers]` |
| `@Cookies('x')`, `@SignedCookies('x')` | `@CookieValue` | `[@cookie "theme"]`, `[@signed_cookie "sid"]`; all: `[@cookies]` |
| `@Session()` | `@SessionAttribute` | `[@session "user_id"]` |
| `@Ip()` | `request.getRemoteAddr()` | `[@ip]` |
| `@HostParam()` | — | `[@host]` |
| custom decorator | `HandlerMethodArgumentResolver` | `[@from guard]` with any `'a Kre.Guard.t` |
| `@UploadedFile('avatar')`, `@UploadedFiles()` | `@RequestPart`, `MultipartFile` | `[@file "avatar"] : Kre.Upload.t`, `[@files "photos"]`, a form field: `[@form "title"]` |
| `@Res()`, `@Next()` | `HttpServletResponse` | not needed: the response is the return value, `next` is middleware |

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

Headers and cookies go into `spec` and OpenAPI (`in: header`, `in: cookie`); headers also go into the generated client: `update ~id ~client_name ?trace ~page_size ~body`.

## Verbs, wildcards, hosts

`[@@get]`, `[@@post]`, `[@@put]`, `[@@patch]`, `[@@delete]`, `[@@head]`, `[@@options]`, `[@@all]` (`@All`: a route for every method). HEAD without its own route is answered by the GET handler without a body. The wildcard `[@@get "*"]` puts the path tail into a `[@wildcard]` parameter. `[@@@host ":account.example.com"]` makes the controller answer only on such hosts (`@Controller({ host })`); `[@host_param "account"]` is a part of the host (`@HostParam`).

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

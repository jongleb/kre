# HTTP-клиент

Nest: `HttpModule` и axios. Spring: `@HttpExchange` на интерфейсе. Symfony: HttpClient. В Kre чужой API описывается сигнатурой, а `[%http_client: …]` делает из неё функтор над адресом и заголовками (как `forRoot`):

<!-- $MDX skip -->
```ocaml
module Github_api =
[%http_client:
  val user : login:string -> Github_user.t [@@get "/users/:login"]
  val repos : login:string -> ?per_page:int -> unit -> Repo.t list
  [@@get "/users/:login/repos"]
  val star : owner:string -> repo:string -> unit [@@put "/user/starred/:owner/:repo"]]

module Github = Github_api (struct
  let url = "https://api.github.com"
  let headers = [ ("Authorization", "Bearer " ^ Settings.config.github_token) ]
end)

let%lwt user = Github.user ~login:"octocat"
```

- Метка, совпадающая с `:сегментом`, идёт в путь; `~body` — тело JSON; остальные метки — query (`?x` — необязательный). Значения разбираются теми же `Kre_shared.Scalar` и dto, что и у контроллеров.
- Ответ — `(T, Kre_client.Error.t) result Lwt.t` (в Melange — `Js.Promise.t`): `T list`, `unit`, `string`, `T.t` с dto, `T.t M.t` через `M.Make`. Ошибки чужого сервера в формате Problem Details разбираются, остальные — `Problem` со статусом.
- Это те же `Kre_client.Http` и `Wire`, что у сгенерированных клиентов, поэтому `Kre_testing.use` отправляет вызовы в обработчик приложения без сети, а `Kre_client.Http.transport` можно подменить в тестах.

Пример и тест — `examples/cats/client_native/test_in_process.ml`.

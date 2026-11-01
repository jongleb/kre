# HTTP client

In Kre a third-party API is described by a signature, and `[%http_client: …]` turns it into a functor over the base URL and headers:

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

- A label matching a `:segment` goes into the path; `~body` is the JSON body; other labels are query parameters (`?x` is optional). Values are parsed by the same `Kre_shared.Scalar` and dto as in controllers.
- The response is `(T, Kre_client.Error.t) result Lwt.t` (in Melange, `Js.Promise.t`): `T list`, `unit`, `string`, `T.t` with dto, `T.t M.t` via `M.Make`. Errors from the remote server in Problem Details format are parsed; the rest become `Problem` with the status.
- These are the same `Kre_client.Http` and `Wire` as in generated clients, so `Kre_testing.use` sends calls to the application's handler without a network, and `Kre_client.Http.transport` can be replaced in tests.

Example and test: `examples/cats/client_native/test_in_process.ml`.

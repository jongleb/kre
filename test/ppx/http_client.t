[%http_client: val …] turns declared calls into a functor over the base URL
and headers; labels matching :segments go in the path, ~body is JSON, other
labels are query parameters.

  $ cat > input.ml <<'ML'
  > module Api = [%http_client:
  >   val user : login:string -> User.t [@@get "/users/:login"]
  >   val repos : login:string -> ?per_page:int -> unit -> Repo.t list [@@get "/users/:login/repos"]
  >   val star : owner:string -> repo:string -> unit [@@put "/user/starred/:owner/:repo"]]
  > ML
  $ ./pp.exe -impl input.ml
  module Api(Config:sig val url : string val headers : (string * string) list
                    end) :
    sig
      val user : login:string -> (User.t, Forge_client.Error.t) result Lwt.t
      val repos :
        login:string ->
          ?per_page:int ->
            unit -> (Repo.t list, Forge_client.Error.t) result Lwt.t
      val star :
        owner:string ->
          repo:string -> (unit, Forge_client.Error.t) result Lwt.t
    end =
    struct
      let user ~login =
        Forge_client.Http.request ~base:Config.url `GET
          ~path:["users";
                Forge_client.Wire.segment (module Forge_shared.Scalar.String)
                  login] ~query:[] ~headers:[Config.headers]
          (Forge_client.Wire.Json (module User))
      let repos ~login ?per_page () =
        Forge_client.Http.request ~base:Config.url `GET
          ~path:["users";
                Forge_client.Wire.segment (module Forge_shared.Scalar.String)
                  login;
                "repos"]
          ~query:[Forge_client.Wire.query (module Forge_shared.Scalar.Int)
                    Forge_shared.Presence.Optional "per_page" per_page]
          ~headers:[Config.headers]
          (Forge_client.Wire.Json (module (Forge_shared.Json.List)(Repo)))
      let star ~owner ~repo =
        Forge_client.Http.request ~base:Config.url `PUT
          ~path:["user";
                "starred";
                Forge_client.Wire.segment (module Forge_shared.Scalar.String)
                  owner;
                Forge_client.Wire.segment (module Forge_shared.Scalar.String)
                  repo] ~query:[] ~headers:[Config.headers]
          Forge_client.Wire.Unit
    end 

A :segment needs its argument; each call needs one verb.

  $ cat > input.ml <<'ML'
  > module Api = [%http_client: val user : unit -> User.t [@@get "/users/:login"]]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 1, characters 28-77:
  1 | module Api = [%http_client: val user : unit -> User.t [@@get "/users/:login"]]
                                  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Error: the path has :login; add ~login to user
  [1]
  $ cat > input.ml <<'ML'
  > module Api = [%http_client: val user : unit -> User.t]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 1, characters 28-53:
  1 | module Api = [%http_client: val user : unit -> User.t]
                                  ^^^^^^^^^^^^^^^^^^^^^^^^^
  Error: user needs one verb with a path: [@@get "/users/:login"]
  [1]

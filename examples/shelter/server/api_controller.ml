[@@@controller "api"]

let cats (module Cats : Cats_service.S) () : Cat.t list Lwt.t =
  Cats.available ()
[@@get "cats"] [@@ability "cats:read"] [@@summary "Cats, for API tokens"]

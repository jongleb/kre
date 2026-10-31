let client : string Forge.Guard.t =
 fun request -> Lwt.return_ok (Dream.client request)

let language : string Forge.Guard.t =
 fun request ->
  Lwt.return_ok
    (Option.value (Dream.header request "Accept-Language") ~default:"en")

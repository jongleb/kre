val json :
  ?status:Dream.status ->
  (module J : Forge_shared.Json.S) -> J.t -> Dream.response Lwt.t

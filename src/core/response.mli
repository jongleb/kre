val json :
  ?status:Dream.status ->
  (module J : Kre_shared.Json.S) -> J.t -> Dream.response Lwt.t

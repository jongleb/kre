val parse :
  's Forge_shared.Search.t -> string -> ('s, Forge_shared.Validation.t) result

val print : 's Forge_shared.Search.t -> 's -> string

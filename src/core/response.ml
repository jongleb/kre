let json ?status (module J : Forge_shared.Json.S) value =
  Dream.json ?status (Jsonkit.to_string (J.to_json value))

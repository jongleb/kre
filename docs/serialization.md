# Serialization

Nest: class-transformer, `@Expose`, `@Exclude`. Forge: `[@@deriving dto]` — это кодеки и JSON Schema из jsonkit; имя в JSON — `[@key]`, значение по умолчанию — `[@default]`.

<!-- $MDX file=examples/profile.ml -->
```ocaml
open Jsonkit.Primitives

type t = {
  display_name : string; [@key "displayName"]
  bio : string; [@default ""]
}
[@@deriving dto]
```

Модуль с `dto` — уже `Forge_shared.Json.S`, поэтому его можно вернуть из хендлера (`Profile.t Lwt.t`) или отдать явно:

<!-- $MDX file=examples/profile_page.ml -->
```ocaml
let respond profile = Forge.Response.json ~status:`OK (module Profile) profile
```

`[@exclude]` и группы `[@expose]` — фаза 2.

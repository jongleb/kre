# Serialization

Nest: class-transformer, `@Expose`, `@Exclude`. Kre: `[@@deriving dto]` — это кодеки и JSON Schema из jsonkit; имя в JSON — `[@key]`, значение по умолчанию — `[@default]`.

<!-- $MDX file=examples/profile.ml -->
```ocaml
open Jsonkit.Primitives

type t = {
  display_name : string; [@key "displayName"]
  bio : string; [@default ""]
}
[@@deriving dto]
```

Модуль с `dto` — уже `Kre_shared.Json.S`, поэтому его можно вернуть из хендлера (`Profile.t Lwt.t`) или отдать явно:

<!-- $MDX file=examples/profile_page.ml -->
```ocaml
let respond profile = Kre.Response.json ~status:`OK (module Profile) profile
```

`[@exclude]` (`@Exclude`, `@JsonIgnore`) — поле принимается на вход, но не уходит в ответ, в схеме `writeOnly`. `[@transform f]` (`@Transform`) — функция над полем при выводе. Mapped types (`PickType`, `OmitType`, `PartialType`) — абстрактный тип того же файла, раскрытый ppx, плюс типизированные функции: `summary_of_t : t -> summary`, `update_apply : update -> t -> t`.

<!-- $MDX file=examples/account.ml -->
```ocaml
open Jsonkit.Primitives

type t = {
  id : int;
  email : string;
  password : string; [@exclude]
  display_name : string; [@key "displayName"] [@transform String.trim]
}
[@@deriving dto]

type summary [@@deriving dto ~pick_of:(t, [ "id"; "display_name" ])]
type update [@@deriving dto ~partial_of:t]
```

Группы `@Expose({ groups })` — отдельные типы-проекции (`~pick_of`) вместо флага в рантайме.

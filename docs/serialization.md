# Serialization

In Kre `[@@deriving dto]` gives codecs and JSON Schema from jsonkit; the JSON name is `[@key]`, the default value is `[@default]`.

<!-- $MDX file=examples/profile.ml -->
```ocaml
open Jsonkit.Primitives

type t = {
  display_name : string; [@key "displayName"]
  bio : string; [@default ""]
}
[@@deriving dto]
```

A module with `dto` is already a `Kre_shared.Json.S`, so it can be returned from a handler (`Profile.t Lwt.t`) or passed explicitly:

<!-- $MDX file=examples/profile_page.ml -->
```ocaml
let respond profile = Kre.Response.json ~status:`OK (module Profile) profile
```

`[@exclude]`: the field is accepted on input but not sent in the response; in the schema it is `writeOnly`. `[@transform f]`: a function applied to the field on output. Mapped types (`~pick_of`, `~omit_of`, `~partial_of`): an abstract type in the same file, expanded by the ppx, plus typed functions: `summary_of_t : t -> summary`, `update_apply : update -> t -> t`.

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

Different views of one type (for example, public and admin) are separate projection types (`~pick_of`) instead of a runtime flag.

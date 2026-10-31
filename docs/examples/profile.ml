open Jsonkit.Primitives

type t = {
  display_name : string; [@key "displayName"]
  bio : string; [@default ""]
}
[@@deriving dto]

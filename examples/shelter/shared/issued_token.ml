open Jsonkit.Primitives

type t = { id : string; token : string; abilities : string list }
[@@deriving dto]

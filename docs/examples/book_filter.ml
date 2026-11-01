open Jsonkit.Primitives

type t = { title : string option } [@@deriving search, dto]

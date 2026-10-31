open Jsonkit.Primitives

type t = { author : string; text : string } [@@deriving dto]

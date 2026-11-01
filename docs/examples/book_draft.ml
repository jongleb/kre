open Jsonkit.Primitives

type t = { title : string [@validate min_length 1] } [@@deriving dto ~strict]

open Jsonkit.Primitives

type t = { abilities : string list } [@@deriving dto ~strict]

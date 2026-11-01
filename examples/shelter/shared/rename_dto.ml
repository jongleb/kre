open Jsonkit.Primitives

type t = { name : Cat.Name.t; version : int } [@@deriving dto ~strict]

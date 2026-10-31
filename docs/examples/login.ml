open Jsonkit.Primitives

type t = { user : string; password : string } [@@deriving dto]

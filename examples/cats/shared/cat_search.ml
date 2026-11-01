open Jsonkit.Primitives

type t = { limit : int; [@default 20] breed : Cat.Breed.t option }
[@@deriving search, dto]

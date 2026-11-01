open Jsonkit.Primitives

type t = { token : string; user : User.t } [@@deriving dto]

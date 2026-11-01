open Jsonkit.Primitives
module Id = Kre_shared.Id.Make ()

type t = { id : Id.t; title : string } [@@deriving dto]

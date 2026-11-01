open Jsonkit.Primitives

type t = {
  name : string option;
  status : Cat.Status.t option;
  age_min : int option;
  age_max : int option;
}
[@@deriving search, dto]

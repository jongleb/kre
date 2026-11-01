open Jsonkit.Primitives

type t = {
  email : Kre_shared.Refined.Email.t;
  password : string; [@validate min_length 8]
}
[@@deriving dto ~strict]

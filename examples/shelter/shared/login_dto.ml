open Jsonkit.Primitives

type t = {
  email : Forge_shared.Refined.Email.t;
  password : string; [@validate min_length 8]
}
[@@deriving dto ~strict]

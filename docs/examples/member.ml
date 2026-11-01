open Jsonkit.Primitives

type t = {
  id : int;
  name : string;
  email : string option; [@groups [ "owner"; "admin" ]]
  notes : string option; [@groups [ "admin" ]]
}
[@@deriving dto]

open Jsonkit.Primitives

type t = {
  id : int;
  email : string;
  password : string; [@exclude]
  display_name : string; [@key "displayName"] [@transform String.trim]
}
[@@deriving dto]

type summary [@@deriving dto ~pick_of:(t, [ "id"; "display_name" ])]
type update [@@deriving dto ~partial_of:t]

type address = { street : string; city : string }

and t = {
  id : int; [@primary] [@auto]
  name : string; [@size 64]
  home : address; [@embedded]
}
[@@deriving table ~name:"people"]

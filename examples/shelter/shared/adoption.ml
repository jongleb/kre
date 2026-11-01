module Id = Forge_shared.Id.Make ()

type t = {
  id : Id.t; [@primary] [@auto] [@column int]
  cat_id : Cat.Id.t; [@column int] [@references Cat] [@unique]
  user_id : User.Id.t; [@column int] [@references User] [@index]
}
[@@deriving table ~name:"adoptions", dto]

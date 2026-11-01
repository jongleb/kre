module Id = Forge_shared.Id.Make ()

type t = {
  id : Id.t; [@primary] [@auto] [@column int]
  cat_id : Cat.Id.t; [@column int] [@references Cat] [@unique]
  user_id : User.Id.t; [@column int] [@references User] [@index]
  adopted_at : Forge_shared.Time.t; [@created_at]
}
[@@deriving table ~name:"adoptions", dto]

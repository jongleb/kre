open Jsonkit.Primitives
module Id = Kre_shared.Id.Make ()

module Name = Kre_shared.Refined.String (struct
  let name = "name"
  let min = 1
  let max = 64
end)

module Age = Kre_shared.Refined.Int (struct
  let name = "age"
  let min = 0
  let max = 40
end)

(** Whether the cat still waits for a home. *)
module Status = struct
  type t = Available | Adopted [@@deriving dto]
end

type t = {
  id : Id.t; [@primary] [@auto] [@column int]
  name : Name.t; [@column string] [@size 64]
  age : Age.t; [@column int]
  status : Status.t; [@column string] [@size 16] [@index]
  owner_id : User.Id.t option; [@column int] [@references User]
  version : int; [@version]
}
[@@deriving table ~name:"cats", dto]

module Id = Forge_shared.Id.Make ()

module Name = Forge_shared.Refined.String (struct
  let name = "name"
  let min = 1
  let max = 64
end)

module Age = Forge_shared.Refined.Int (struct
  let name = "age"
  let min = 0
  let max = 40
end)

module Breed = Forge_shared.Refined.Enum (struct
  let name = "breed"
  let values = [ "siamese"; "persian"; "maine coon" ]
end)

type t = {
  id : Id.t; [@primary] [@auto] [@column int]
  name : Name.t; [@column string] [@size 64]
  age : Age.t; [@column int]
  breed : Breed.t; [@column string] [@size 32] [@index]
}
[@@deriving table ~name:"cats", dto]

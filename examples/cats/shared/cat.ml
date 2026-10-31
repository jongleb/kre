open Jsonkit.Primitives

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

type t = { id : int; name : Name.t; age : Age.t; breed : Breed.t }
[@@deriving dto]

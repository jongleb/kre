open Jsonkit.Primitives

type t = {
  name : Cat.Name.t;
  age : Cat.Age.t;
  breed : Cat.Breed.t;
  note : string; [@default ""] [@validate max_length 16]
}
[@@deriving dto ~strict]

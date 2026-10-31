type t = { name : Cat.Name.t; age : Cat.Age.t; breed : Cat.Breed.t }
[@@deriving json, jsonschema]

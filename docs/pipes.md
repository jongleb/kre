# Pipes

Nest: `ParseIntPipe`, `ValidationPipe`, custom pipes. Kre: parsing follows from the parameter type. The `Kre_shared.Scalar` modules parse `int`, `int64`, `float`, `bool`, `string`; custom parsing is a custom module with `of_string`, for example an opaque type from `Kre_shared.Refined`. A value that did not parse never reaches the handler: path → 404, query → 400, body → 422.

<!-- $MDX file=../examples/cats/shared/cat.ml -->
```ocaml
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

module Breed = Kre_shared.Refined.Enum (struct
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
```

`Cat.Breed.t` can be taken directly as a path parameter, `~(breed : Cat.Breed.t)`: the ppx inserts `(module Cat.Breed)`, and `"/cats/sphynx"` gets 404 before the handler runs. Body checks are in [Validation](validation.md).

If you need to pattern-match on the value, a variant without arguments with `[@@deriving dto]` works instead of `Refined.Enum`. The deriver turns it into a scalar (`name`, `of_string`, `to_string`, a JSON string, JSON Schema `enum`), so it fits a path, a query, a body and `[@column string]` in a table. The string is the constructor name in lower case; `[@key "on hold"]` sets a custom one:

<!-- $MDX skip -->
```ocaml
module Status = struct
  type t = Available | Adopted [@@deriving dto]
end
```

`Cat.Status.of_string "sold"` gives a `one_of` rule error; the full example is `examples/shelter/shared/cat.ml`.

# Pipes

Nest: `ParseIntPipe`, `ValidationPipe`, свои pipes. Forge: разбор следует из типа параметра. `int`, `int64`, `float`, `bool`, `string` разбирают модули `Forge_shared.Scalar`; свой разбор — свой модуль с `of_string`, например opaque-тип из `Forge_shared.Refined`. Значение, которое не разобралось, до хендлера не доходит: path → 404, query → 400, тело → 422.

<!-- $MDX file=../examples/cats/shared/cat.ml -->
```ocaml
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
```

`Cat.Breed.t` можно принять прямо параметром пути — `~(breed : Cat.Breed.t)`: ppx подставит `(module Cat.Breed)`, а `"/cats/sphynx"` получит 404 ещё до хендлера. Проверки тела — в [Validation](validation.md).

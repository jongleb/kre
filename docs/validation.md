# Validation

Nest: class-validator и `ValidationPipe`. Kre: parse, don't validate. Лучший путь — поля opaque-типов из `Kre_shared.Refined`: невалидное значение нельзя даже построить. Разовые правила — `[@validate …]` на поле; правила — значения `Kre_shared.Validation`.

<!-- $MDX file=../examples/cats/shared/create_cat_dto.ml -->
```ocaml
open Jsonkit.Primitives

type t = {
  name : Cat.Name.t;
  age : Cat.Age.t;
  breed : Cat.Breed.t;
  note : string; [@default ""] [@validate max_length 16]
}
[@@deriving dto ~strict]
```

Ошибка тела — 422 со списком нарушенных правил и путём поля:

```json
{ "type": "urn:kre:error:validation", "title": "Unprocessable Entity", "status": 422,
  "detail": "validation failed", "instance": "/cats",
  "errors": [ { "path": ["note"], "rule": "max_length", "message": "must be at most 16 characters" } ] }
```

`~strict` отвергает неизвестные поля. Правила `[@validate]` проверяются все, ошибки накапливаются.

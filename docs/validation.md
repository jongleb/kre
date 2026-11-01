# Validation

Kre follows the rule "parse, don't validate". The best way is fields of opaque types from `Kre_shared.Refined`: an invalid value cannot even be built. One-off rules are `[@validate …]` on a field; rules are values of `Kre_shared.Validation`.

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

A body error is 422 with the list of broken rules and the field path:

```json
{ "type": "urn:kre:error:validation", "title": "Unprocessable Entity", "status": 422,
  "detail": "validation failed", "instance": "/cats",
  "errors": [ { "path": ["note"], "rule": "max_length", "message": "must be at most 16 characters" } ] }
```

`~strict` rejects unknown fields. All `[@validate]` rules are checked, and errors accumulate.

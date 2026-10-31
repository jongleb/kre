# Custom providers

Nest: `useValue`, `useClass`, `useFactory`. Forge: любой другой модуль той же сигнатуры. Подмена — передать его в `register`.

<!-- $MDX file=examples/fake_cats.mli -->
```ocaml
include Cats_service.S
```

<!-- $MDX file=examples/fake_cats.ml -->
```ocaml
let tom =
  {
    Cat.id = 1;
    name = Result.get_ok (Cat.Name.of_repr "tom");
    age = Result.get_ok (Cat.Age.of_repr 3);
    breed = Result.get_ok (Cat.Breed.of_repr "siamese");
  }

let add (_ : Create_cat_dto.t) = Lwt.return tom
let find_all () = Lwt.return [ tom ]
let find id = Lwt.return (match id with 1 -> Some tom | _ -> None)
```

<!-- $MDX file=examples/composition.ml -->
```ocaml
let controllers ~fake =
  match fake with
  | `Fake -> [ Cats_controller.register (module Fake_cats) ]
  | `Real -> [ Cats_controller.register (module Cats_service) ]
```

Фабрика (`useFactory`) — обычный код в `main.ml` до `Forge.App.run`: прочитать конфиг, открыть пул, применить функтор.

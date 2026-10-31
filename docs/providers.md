# Providers

Nest: `@Injectable()` класс-синглтон, который контейнер внедряет в конструктор контроллера. Forge: модуль. Его `.mli` с `module type S` — контракт, состояние — значения верхнего уровня, внедрение — параметр `(module Cats : Cats_service.S)` у хендлера.

<!-- $MDX file=../examples/cats/server/cats_service.mli -->
```ocaml
(** The cats provider. *)
module type S = sig
  val add : Create_cat_dto.t -> Cat.t Lwt.t
  val find_all : unit -> Cat.t list Lwt.t
  val find : int -> Cat.t option Lwt.t
end

module Make () : S
(** A provider with its own state; [new CatsService()]. *)

include S
```

<!-- $MDX file=../examples/cats/server/cats_service.ml -->
```ocaml
module type S = sig
  val add : Create_cat_dto.t -> Cat.t Lwt.t
  val find_all : unit -> Cat.t list Lwt.t
  val find : int -> Cat.t option Lwt.t
end

module Make () = struct
  let cats : Cat.t Dynarray.t = Dynarray.create ()

  let add ({ name; age; breed } : Create_cat_dto.t) =
    let cat = { Cat.id = Dynarray.length cats + 1; name; age; breed } in
    Dynarray.add_last cats cat;
    Lwt.return cat

  let find_all () = Lwt.return (Dynarray.to_list cats)

  let find id =
    Lwt.return (Dynarray.find_opt (fun (cat : Cat.t) -> cat.id = id) cats)
end

include Make ()
```

`Make ()` — генеративный функтор: каждое применение даёт новое состояние, как `new CatsService()`; `include Make ()` — тот единственный экземпляр, который в Nest держит контейнер. Подключение — в composition root: `Cats_controller.register (module Cats_service)`; в тесте — свежий экземпляр: `let module Fresh = Cats_service.Make () in Cats_controller.register (module Fresh)`. Забыли передать модуль — ошибка компиляции, а не старта.

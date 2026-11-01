# Providers

A provider is a module. Its `.mli` with `module type S` is the contract, the state is top-level values, injection is a `(module Cats : Cats_service.S)` parameter of the handler.

<!-- $MDX file=../examples/cats/server/cats_service.mli -->
```ocaml
(** The cats provider. *)
module type S = sig
  val add : Create_cat_dto.t -> Cat.t Lwt.t
  val find_all : unit -> Cat.t list Lwt.t
  val find : Cat.Id.t -> Cat.t option Lwt.t
end

module Make () : S
(** A provider with its own state: each application is a fresh instance. *)

include S
```

<!-- $MDX file=../examples/cats/server/cats_service.ml -->
```ocaml
module type S = sig
  val add : Create_cat_dto.t -> Cat.t Lwt.t
  val find_all : unit -> Cat.t list Lwt.t
  val find : Cat.Id.t -> Cat.t option Lwt.t
end

module Make () = struct
  let cats : Cat.t Dynarray.t = Dynarray.create ()
  let last_id = ref None

  let add ({ name; age; breed } : Create_cat_dto.t) =
    let id = Option.fold ~none:Cat.Id.first ~some:Cat.Id.succ !last_id in
    last_id := Some id;
    let cat = { Cat.id; name; age; breed } in
    Dynarray.add_last cats cat;
    Kre.Live.publish [ "cats" ];
    Lwt.return cat

  let find_all () = Lwt.return (Dynarray.to_list cats)

  let find id =
    Lwt.return
      (Dynarray.find_opt (fun (cat : Cat.t) -> Cat.Id.equal cat.id id) cats)
end

include Make ()
```

`Make ()` is a generative functor: each application gives new state; `include Make ()` is the single instance the whole application shares. Wiring happens in the composition root: `Cats_controller.register (module Cats_service)`; in a test, a fresh instance: `let module Fresh = Cats_service.Make () in Cats_controller.register (module Fresh)`. Forgetting to pass the module is a compile error, not a startup error.

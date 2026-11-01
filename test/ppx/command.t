[@@command "doc"] on a function makes it a command of the binary: module
parameters are providers that [%wire] passes, labelled ones are options.

  $ cat > input.ml <<'ML'
  > let seed (module Cats : Cats_service.S) ~(count : int) ?(breed : Breed.t = Breed.default) () : unit Lwt.t =
  >   Cats.seed ~count ~breed
  > [@@command "Seed cats"]
  > 
  > let hello () : unit Lwt.t = Lwt.return_unit [@@command "Say hello"]
  > ML
  $ ./pp.exe -impl input.ml
  let seed ((module Cats)  : (module Cats_service.S)) ~count:(count : int)
    ?breed:((breed : Breed.t)= Breed.default) () : unit Lwt.t=
    Cats.seed ~count ~breed
  let __forge_command_seed ((module Cats)  : (module Cats_service.S)) =
    Forge.Command.make ~name:"seed" ~doc:"Seed cats"
      ~options:["count"; "breed"]
      (fun __forge_args ->
         let open Forge_shared.Validation.Syntax in
           let+ count =
             Forge.Command.required (module Forge_shared.Scalar.Int) "count"
               __forge_args
           and+ breed =
             Forge.Command.optional (module Breed) "breed"
               ~default:Breed.default __forge_args in
           fun () -> seed (module Cats) ~count ~breed ())
  let hello () : unit Lwt.t= Lwt.return_unit
  let __forge_command_hello () =
    Forge.Command.make ~name:"hello" ~doc:"Say hello" ~options:[]
      (fun __forge_args -> Ok (fun () -> hello ()))

Options are scalars; the attribute takes a description.

  $ cat > input.ml <<'ML'
  > let f ~(ids : int list) () : unit Lwt.t = Lwt.return_unit [@@command "x"]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 1, characters 14-22:
  1 | let f ~(ids : int list) () : unit Lwt.t = Lwt.return_unit [@@command "x"]
                    ^^^^^^^^
  Error: a command option is int, int64, float, bool, string or M.t with M a Forge_shared.Scalar.S
  [1]
  $ cat > input.ml <<'ML'
  > let f () : unit Lwt.t = Lwt.return_unit [@@command]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 1, characters 40-51:
  1 | let f () : unit Lwt.t = Lwt.return_unit [@@command]
                                              ^^^^^^^^^^^
  Error: [@@command] takes what the command does: [@@command "Seed the database"]
  [1]

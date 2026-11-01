# Guards

Nest: `CanActivate` and `@UseGuards`. Kre: a guard is a function `Dream.request -> ('a, Kre.Error.t) result Lwt.t` (`'a Kre.Guard.t`). `[@@@guards [ g ]]` and `[@@guards [ g ]]` only check (`unit Kre.Guard.t`); a `[@guard g]` parameter checks **and** passes the result to the handler.

It works best when a guard returns evidence: a value of a type that cannot be obtained any other way:

<!-- $MDX file=examples/roles.ml -->
```ocaml
module Admin : sig
  type t

  val of_header : string option -> t option
end = struct
  type t = Admin

  let of_header = function Some "admin" -> Some Admin | Some _ | None -> None
end

let admin : Admin.t Kre.Guard.t =
 fun request ->
  Lwt.return
    (Option.to_result
       ~none:(Kre.Error.forbidden "admins only")
       (Admin.of_header (Dream.header request "X-Role")))

let signed_in : unit Kre.Guard.t =
 fun request ->
  Lwt.return
    (Option.fold
       ~none:(Error (Kre.Error.unauthorized "sign in first"))
       ~some:(fun _ -> Ok ())
       (Dream.header request "X-User"))

let user : string Kre.Guard.t =
 fun request ->
  Lwt.return
    (Option.to_result
       ~none:(Kre.Error.unauthorized "sign in first")
       (Dream.header request "X-User"))
```

<!-- $MDX file=examples/admin_controller.ml -->
```ocaml
[@@@controller "admin"]
[@@@guards [ Roles.signed_in ]]

let purge (module Cats : Cats_service.S)
    ~admin:(_ : (Roles.Admin.t[@guard Roles.admin])) () : unit Lwt.t =
  Lwt.map ignore (Cats.find_all ())
[@@delete "cats"]
```

`purge` cannot be called without `Roles.Admin.t`, and only `Roles` can create one. Order: `[@@@guards]` → `[@@guards]` → `[@guard]` parameters from left to right; the first error becomes the response (401, then 403).

A check that needs parsed parameters (does the user own this record) is `[@@authorize]`: the closure gets the handler arguments by label and runs before the body.

<!-- $MDX file=examples/notes_controller.ml -->
```ocaml
[@@@controller "notes"]

let owners = [ (1, "ann"); (2, "bob") ]

let owns ~user ~id =
  Lwt.return
    (match List.assoc_opt id owners with
    | Some owner when String.equal owner user -> Ok ()
    | Some _ | None -> Error (Kre.Error.forbidden "not your note"))

let read ~(user : (string[@guard Roles.user])) ~(id : int) : string Lwt.t =
  Lwt.return (Printf.sprintf "note %d for %s" id user)
[@@get ":id"] [@@authorize fun ~user ~id -> owns ~user ~id]
```

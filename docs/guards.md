# Guards

Nest: `CanActivate` и `@UseGuards`. Forge: guard — функция `Dream.request -> ('a, Forge.Error.t) result Lwt.t` (`'a Forge.Guard.t`). `[@@@guards [ g ]]` и `[@@guards [ g ]]` только проверяют (`unit Forge.Guard.t`); параметр `[@guard g]` проверяет **и** передаёт хендлеру результат.

Лучше всего, когда guard возвращает доказательство — значение типа, который нельзя получить иначе:

<!-- $MDX file=examples/roles.ml -->
```ocaml
module Admin : sig
  type t

  val of_header : string option -> t option
end = struct
  type t = Admin

  let of_header = function Some "admin" -> Some Admin | Some _ | None -> None
end

let admin : Admin.t Forge.Guard.t =
 fun request ->
  Lwt.return
    (Option.to_result
       ~none:(Forge.Error.forbidden "admins only")
       (Admin.of_header (Dream.header request "X-Role")))

let signed_in : unit Forge.Guard.t =
 fun request ->
  Lwt.return
    (Option.fold
       ~none:(Error (Forge.Error.unauthorized "sign in first"))
       ~some:(fun _ -> Ok ())
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

`purge` нельзя вызвать без `Roles.Admin.t`, а создать его может только `Roles`. Порядок: `[@@@guards]` → `[@@guards]` → параметры `[@guard]` слева направо; первая ошибка становится ответом (401, затем 403).

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

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

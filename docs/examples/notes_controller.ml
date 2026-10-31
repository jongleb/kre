[@@@controller "notes"]

let owners = [ (1, "ann"); (2, "bob") ]

let owns ~user ~id =
  Lwt.return
    (match List.assoc_opt id owners with
    | Some owner when String.equal owner user -> Ok ()
    | Some _ | None -> Error (Forge.Error.forbidden "not your note"))

let read ~(user : (string[@guard Roles.user])) ~(id : int) : string Lwt.t =
  Lwt.return (Printf.sprintf "note %d for %s" id user)
[@@get ":id"] [@@authorize fun ~user ~id -> owns ~user ~id]

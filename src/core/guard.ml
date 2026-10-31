type 'a t = Dream.request -> ('a, Error.t) result Lwt.t

let field field ~missing request =
  Lwt.return (Option.to_result ~none:missing (Dream.field request field))

let header name request =
  Lwt.return
    (Option.to_result
       ~none:(Error.bad_request ("missing header " ^ name))
       (Dream.header request name))

let both left right request = Lwt_result.both (left request) (right request)

let session name request =
  Lwt.return
    (Option.to_result
       ~none:(Error.unauthorized "not signed in")
       (Dream.session_field request name))

let map f guard request = Lwt_result.map f (guard request)

let check f guard request =
  Lwt.map (fun found -> Result.bind found f) (guard request)

let optional guard request =
  Lwt.map (fun found -> Ok (Result.to_option found)) (guard request)

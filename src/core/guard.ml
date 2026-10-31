type 'a t = Dream.request -> ('a, Error.t) result Lwt.t

let field field ~missing request =
  Lwt.return (Option.to_result ~none:missing (Dream.field request field))

let header name request =
  Lwt.return
    (Option.to_result
       ~none:(Error.bad_request ("missing header " ^ name))
       (Dream.header request name))

let both left right request = Lwt_result.both (left request) (right request)

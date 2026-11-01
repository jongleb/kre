let run ?(backoff = 0.) ~attempts f =
  let rec attempt left delay =
    Lwt.catch f (fun exn ->
        match left with
        | left when left <= 1 -> Lwt.reraise exn
        | _ ->
            Lwt.bind (Lwt_unix.sleep delay) (fun () ->
                attempt (left - 1) (delay *. 2.)))
  in
  attempt attempts backoff

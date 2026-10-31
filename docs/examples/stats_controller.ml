[@@@controller "stats"]

let computed = ref 0

let summary () : string Lwt.t =
  incr computed;
  Lwt.return (Printf.sprintf "computed %d times" !computed)
[@@get] [@@cache 60.0]

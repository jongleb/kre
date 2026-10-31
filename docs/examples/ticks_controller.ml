[@@@controller "ticks"]

let count ~(upto : int) : Tick.t Lwt_stream.t Lwt.t =
  Lwt.return (Lwt_stream.of_list (List.init upto (fun n -> { Tick.n })))
[@@get] [@@sse]

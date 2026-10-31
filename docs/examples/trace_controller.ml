[@@@controller "trace"]
[@@@use [ Request_id.use ]]

let show ~(id : (int[@guard Request_id.current])) () : string Lwt.t =
  Lwt.return (Printf.sprintf "request %d" id)
[@@get]

[@@@gateway "chat"]

let say (socket : Kre.Gateway.socket) ~(body : Chat_line.t) : Chat_line.t Lwt.t
    =
  let%lwt () =
    Kre.Gateway.broadcast socket ~event:"said" (module Chat_line) body
  in
  Lwt.return { body with text = "ack: " ^ body.text }
[@@subscribe "say"]

let ping () : string Lwt.t = Lwt.return "pong" [@@subscribe "ping"]

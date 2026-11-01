# WebSockets

In Kre WebSocket handlers live in a gateway file.

<!-- $MDX file=examples/chat_gateway.ml -->
```ocaml
[@@@gateway "chat"]

let say (socket : Kre.Gateway.socket) ~(body : Chat_line.t) : Chat_line.t Lwt.t
    =
  let%lwt () =
    Kre.Gateway.broadcast socket ~event:"said" (module Chat_line) body
  in
  Lwt.return { body with text = "ack: " ^ body.text }
[@@subscribe "say"]

let ping () : string Lwt.t = Lwt.return "pong" [@@subscribe "ping"]
```

- `[@@@gateway "chat"]`: a WebSocket on `/chat`; frames are `{"event": "say", "data": …}`.
- `[@@subscribe "say"]`: an event handler; `~(body : T.t)` is the data, `(socket : Kre.Gateway.socket)` is the client, `(module M : S)` are dependencies.
- A `T.t Lwt.t` result goes back to the sender under the same event; `unit Lwt.t` means no reply; `Kre.Gateway.broadcast` sends to all clients of the gateway.
- A parse or handler error is an `error` event with Problem Details; an unknown event is a 404 in the same format.

The ppx generates `gateway` (the gateway itself; it is convenient in tests via `Kre.Gateway.connect`) and `register` (a controller for `Kre.App`).

# WebSockets

Nest: `@WebSocketGateway`, `@SubscribeMessage('event')`, `@MessageBody`, `@ConnectedSocket`. Spring: `@MessageMapping`. Forge: файл-шлюз.

<!-- $MDX file=examples/chat_gateway.ml -->
```ocaml
[@@@gateway "chat"]

let say (socket : Forge.Gateway.socket) ~(body : Chat_line.t) :
    Chat_line.t Lwt.t =
  let%lwt () =
    Forge.Gateway.broadcast socket ~event:"said" (module Chat_line) body
  in
  Lwt.return { body with text = "ack: " ^ body.text }
[@@subscribe "say"]

let ping () : string Lwt.t = Lwt.return "pong" [@@subscribe "ping"]
```

- `[@@@gateway "chat"]` — WebSocket на `/chat`; кадры `{"event": "say", "data": …}`, как у адаптера Nest.
- `[@@subscribe "say"]` — обработчик события; `~(body : T.t)` — данные (`@MessageBody`), `(socket : Forge.Gateway.socket)` — клиент (`@ConnectedSocket`), `(module M : S)` — зависимости.
- Результат `T.t Lwt.t` уходит отправителю тем же событием; `unit Lwt.t` — без ответа; `Forge.Gateway.broadcast` — всем клиентам шлюза.
- Ошибка разбора или хендлера — событие `error` с Problem Details; неизвестное событие — 404 в том же формате.

ppx генерирует `gateway` (сам шлюз — им удобно пользоваться в тестах через `Forge.Gateway.connect`) и `register` (контроллер для `Forge.App`).

# Events

Nest: `EventEmitter2` и `@OnEvent('user.created')`. Spring: `ApplicationEventPublisher` и `@EventListener`. Forge: типизированный топик, шина-провайдер и `[@@on_event]`.

- Топик — значение с типом события: `Forge.Events.topic "user.signed_up" : Signup.t Forge.Events.topic`. Опубликовать в него событие другого типа нельзя.
- Шина — провайдер `Forge.Events.Make ()`; кто публикует, получает её параметром (`(module Bus : Forge.Events.S)`).
- Слушатель — функция провайдера с `[@@on_event Topics.user_signed_up]`. `[%wire]` при сборке подписывает её на шину; нет шины — ошибка компиляции.
- `publish` вызывает слушателей параллельно; исключение слушателя пишется в лог и не ломает публикацию.

<!-- $MDX file=../examples/events/server/topics.ml -->
```ocaml
let user_signed_up : Signup.t Forge.Events.topic =
  Forge.Events.topic "user.signed_up"
```

<!-- $MDX file=../examples/events/server/mailer.ml -->
```ocaml
module type S = sig
  val sent : unit -> string list
  val welcome : Signup.t -> unit Lwt.t
end

module Make () = struct
  let outbox = ref []
  let sent () = List.rev !outbox

  let welcome (signup : Signup.t) =
    outbox := ("welcome " ^ signup.email) :: !outbox;
    Lwt.return_unit
  [@@on_event Topics.user_signed_up]
end
```

<!-- $MDX file=../examples/events/server/signup_controller.ml -->
```ocaml
[@@@controller "signup"]

let create (module Bus : Forge.Events.S) ~(body : Signup.t) () : unit Lwt.t =
  Bus.publish Topics.user_signed_up body
[@@post]

let outbox (module Mailer : Mailer.S) () : string list Lwt.t =
  Lwt.return (Mailer.sent ())
[@@get "outbox"]
```

Разнотипные подписки хранятся без `Obj.magic`: топик несёт `Type.Id.t`, и шина выбирает слушателей по доказательству равенства типов.

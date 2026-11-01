# Events

Nest: `EventEmitter2` и `@OnEvent('user.created')`. Spring: `ApplicationEventPublisher` и `@EventListener`. Kre: типизированный топик, шина-провайдер и `[@@on_event]`.

- Топик — значение с типом события: `Kre.Events.topic "user.signed_up" : Signup.t Kre.Events.topic`. Опубликовать в него событие другого типа нельзя.
- Шина — провайдер `Kre.Events.Make ()`; кто публикует, получает её параметром (`(module Bus : Kre.Events.S)`).
- Слушатель — функция провайдера с `[@@on_event Topics.user_signed_up]`. `[%wire]` при сборке подписывает её на шину; нет шины — ошибка компиляции.
- `publish` вызывает слушателей параллельно; исключение слушателя пишется в лог и не ломает публикацию.

<!-- $MDX file=../examples/events/server/topics.ml -->
```ocaml
let user_signed_up : Signup.t Kre.Events.topic =
  Kre.Events.topic "user.signed_up"
```

<!-- $MDX file=../examples/events/server/mailer.ml -->
```ocaml
module type S = sig
  val sent : unit -> string list
  val welcome : Signup.t -> unit Lwt.t
  val digests : unit -> int
  val digest : unit -> unit Lwt.t
  val healthy : unit -> (unit, string) result Lwt.t
end

module Make () = struct
  let outbox = ref []
  let sent () = List.rev !outbox

  let welcome (signup : Signup.t) =
    outbox := ("welcome " ^ signup.email) :: !outbox;
    Lwt.return_unit
  [@@on_event Topics.user_signed_up]

  let sent_digests = ref 0
  let digests () = !sent_digests

  let digest () =
    incr sent_digests;
    Lwt.return_unit
  [@@interval 0.02]

  let healthy () = Lwt.return_ok () [@@health "mailer"]
end
```

<!-- $MDX file=../examples/events/server/signup_controller.ml -->
```ocaml
[@@@controller "signup"]

let create (module Bus : Kre.Events.S) ~(body : Signup.t) () : unit Lwt.t =
  Bus.publish Topics.user_signed_up body
[@@post]

let outbox (module Mailer : Mailer.S) () : string list Lwt.t =
  Lwt.return (Mailer.sent ())
[@@get "outbox"]

let digests (module Mailer : Mailer.S) () : int Lwt.t =
  Lwt.return (Mailer.digests ())
[@@get "digests"]
```

Разнотипные подписки хранятся без `Obj.magic`: топик несёт `Type.Id.t`, и шина выбирает слушателей по доказательству равенства типов.

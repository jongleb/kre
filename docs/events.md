# Events

Nest: `EventEmitter2` and `@OnEvent('user.created')`. Spring: `ApplicationEventPublisher` and `@EventListener`. Kre: a typed topic, a bus provider and `[@@on_event]`.

- A topic is a value carrying the event type: `Kre.Events.topic "user.signed_up" : Signup.t Kre.Events.topic`. An event of a different type cannot be published to it.
- The bus is the provider `Kre.Events.Make ()`; whoever publishes receives it as a parameter (`(module Bus : Kre.Events.S)`).
- A listener is a provider function with `[@@on_event Topics.user_signed_up]`. `[%wire]` subscribes it to the bus during the build; no bus is a compile error.
- `publish` calls listeners in parallel; a listener's exception is logged and does not break the publish.

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

let notify (module Notifications : Notifications.S) () : string list Lwt.t =
  Lwt.return (Notifications.send "ann@x.io")
[@@get "notify"]

let greet (module Greeting : Greeting.S) () : string Lwt.t =
  Lwt.return (Greeting.hello "ann")
[@@get "greet"]
```

Subscriptions of different types are stored without `Obj.magic`: a topic carries a `Type.Id.t`, and the bus selects listeners by a proof of type equality.

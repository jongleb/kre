# Task scheduling

Nest: `@Cron('0 3 * * *')`, `@Interval(30000)`, `@Timeout(5000)`. Spring: `@Scheduled(cron=…, fixedRate=…, initialDelay=…)`. Forge: атрибут на функции провайдера `unit -> unit Lwt.t`.

| Атрибут | Когда |
| --- | --- |
| `[@@cron "0 3 * * *"]` | по cron-выражению (минута час день месяц день-недели, UTC) |
| `[@@interval 30.0]` | каждые N секунд |
| `[@@after 5.0]` | один раз через N секунд после старта (`@Timeout`) |

`[%wire]` собирает задачи всех провайдеров: `on_start` их запускает, `on_shutdown` останавливает. Cron-выражение разбирается при сборке — `[@@cron "61 * * * *"]` не компилируется (`minute 61 is outside 0-59`). Исключение задачи пишется в лог и не останавливает расписание.

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

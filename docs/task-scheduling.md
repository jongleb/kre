# Task scheduling

Nest: `@Cron('0 3 * * *')`, `@Interval(30000)`, `@Timeout(5000)`. Spring: `@Scheduled(cron=…, fixedRate=…, initialDelay=…)`. Kre: an attribute on a provider function `unit -> unit Lwt.t`.

| Attribute | When |
| --- | --- |
| `[@@cron "0 3 * * *"]` | by a cron expression (minute hour day month day-of-week, UTC) |
| `[@@interval 30.0]` | every N seconds |
| `[@@after 5.0]` | once, N seconds after start (`@Timeout`) |

`[%wire]` collects the tasks of all providers: `on_start` starts them, `on_shutdown` stops them. The cron expression is parsed at build time: `[@@cron "61 * * * *"]` does not compile (`minute 61 is outside 0-59`). A task's exception is logged and does not stop the schedule.

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

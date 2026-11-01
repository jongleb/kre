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

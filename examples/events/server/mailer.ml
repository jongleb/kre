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

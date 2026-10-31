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

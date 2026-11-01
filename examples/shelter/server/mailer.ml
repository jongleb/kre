module type S = sig
  val sent : unit -> string list
end

let outbox = ref []

let congratulate (adoption : Adoption.t) =
  outbox :=
    Printf.sprintf "user %s adopted cat %s"
      (User.Id.to_string adoption.user_id)
      (Cat.Id.to_string adoption.cat_id)
    :: !outbox;
  Lwt.return_ok ()
[@@job Queues.congratulate]

let sent () = List.rev !outbox

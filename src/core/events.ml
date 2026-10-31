type 'a topic = { name : string; id : 'a Type.Id.t }

let topic name = { name; id = Type.Id.make () }
let name topic = topic.name

module type S = sig
  val publish : 'a topic -> 'a -> unit Lwt.t
  val subscribe : 'a topic -> ('a -> unit Lwt.t) -> unit
end

(** A subscription to some topic, whatever its event type. *)
type listener = Listener : 'a topic * ('a -> unit Lwt.t) -> listener

module Make () = struct
  let listeners = ref []

  let subscribe topic handle =
    listeners := !listeners @ [ Listener (topic, handle) ]

  let publish (type a) (topic : a topic) (event : a) =
    let deliver (Listener (subscribed, handle)) =
      match Type.Id.provably_equal subscribed.id topic.id with
      | Some Type.Equal ->
          Some
            (Lwt.catch
               (fun () -> handle event)
               (fun exn ->
                 Dream.error (fun log ->
                     log "listener of %s failed: %s" topic.name
                       (Printexc.to_string exn));
                 Lwt.return_unit))
      | None -> None
    in
    Lwt.join (List.filter_map deliver !listeners)
end

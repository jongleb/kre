type 'a topic
(** A named, typed event channel. *)

val topic : string -> 'a topic
val name : 'a topic -> string

(** An event bus; [Make ()] gives one, injected like any provider. *)
module type S = sig
  val publish : 'a topic -> 'a -> unit Lwt.t
  val subscribe : 'a topic -> ('a -> unit Lwt.t) -> unit
end

module Make () : S

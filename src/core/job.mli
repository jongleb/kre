type 'a queue
(** A named queue whose payloads are one dto type. *)

type handler
(** What runs a queue's payloads; [[@@job q]] on a provider function. *)

val queue : string -> (module Forge_shared.Json.S with type t = 'a) -> 'a queue
val handle : 'a queue -> ('a -> (unit, string) result Lwt.t) -> handler
val table : Table.t

(** A job runner over one database: a provider. *)
module type S = sig
  val enqueue : ?delay:float -> 'a queue -> 'a -> unit Lwt.t
  val register : handler -> unit
  val drain : unit -> int Lwt.t
  val on_start : unit -> unit Lwt.t
  val on_shutdown : unit -> unit Lwt.t
end

module Make
    (Db : Db.S)
    (Config : sig
      val poll : float
      val attempts : int
    end) : S

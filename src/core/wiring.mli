type t = private {
  controllers : Controller.t list;
  on_start : unit -> unit Lwt.t;  (** Provider hooks, in dependency order. *)
  on_shutdown : unit -> unit Lwt.t;  (** The same hooks, in reverse. *)
}
(** An application assembled by [[%wire]]. *)

val make :
  controllers:Controller.t list ->
  on_start:(unit -> unit Lwt.t) list ->
  on_shutdown:(unit -> unit Lwt.t) list ->
  t

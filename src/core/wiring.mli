type t = private {
  controllers : Controller.t list;
  on_start : unit -> unit Lwt.t;  (** Provider hooks, in dependency order. *)
  on_shutdown : unit -> unit Lwt.t;  (** The same hooks, in reverse. *)
  health : Actuator.check list;  (** [[@@health]] functions of the providers. *)
  beans : Actuator.bean list;
      (** Providers in start order, then controllers, with what each got. *)
}
(** An application assembled by [[%wire]]. *)

val make :
  controllers:Controller.t list ->
  on_start:(unit -> unit Lwt.t) list ->
  on_shutdown:(unit -> unit Lwt.t) list ->
  ?jobs:Schedule.job list ->
  ?health:Actuator.check list ->
  ?beans:Actuator.bean list ->
  unit ->
  t

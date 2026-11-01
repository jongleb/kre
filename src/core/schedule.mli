(** When a job runs: every few seconds, once after start, or on a cron line. *)
type timing = Every of float | After of float | Cron of Kre_shared.Cron.t

type job

val job : name:string -> timing -> (unit -> unit Lwt.t) -> job
val start : job list -> unit -> unit Lwt.t

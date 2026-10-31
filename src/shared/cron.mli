type t
(** A parsed five-field cron schedule: minute hour day month weekday. *)

val of_string : string -> (t, string) result

val of_string_exn : string -> t
(** For expressions the ppx already checked at build time. *)

val next : t -> after:float -> float option

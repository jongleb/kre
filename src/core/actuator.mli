type check = { name : string; run : unit -> (unit, string) result Lwt.t }
(** A health check; [[@@health "name"]] on a provider function makes one. *)

type bean = { name : string; needs : string list }
(** A provider or controller of the application and what it was given. *)

(** Who may read the actuator. *)
type access = Loopback | Anyone

type t = private { controller : Controller.t; metrics : Dream.middleware }

val make :
  ?checks:check list ->
  ?info:(string * string) list ->
  ?env:(string * string) list ->
  ?beans:bean list ->
  ?access:access ->
  Controller.t list ->
  t

val mermaid : bean list -> string

type entry = {
  method_ : string;
  target : string;
  status : int;
  milliseconds : float;
  queries : string list;  (** SQL in the order it ran. *)
}
(** One request as the profiler saw it. *)

val sql : string -> unit
val middleware : Dream.middleware
val controller : Controller.t
val recent : unit -> entry list
val repeated : entry -> (string * int) list

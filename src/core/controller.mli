type t = private {
  spec : Spec.t;
  middleware : Dream.middleware list;  (** [[@@@use]], around every route. *)
  routes : Route.t list;
}
(** A mounted controller: its routes and their description. *)

val v : ?middleware:Dream.middleware list -> spec:Spec.t -> Route.t list -> t

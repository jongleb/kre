type t = private {
  spec : Spec.t;
  middleware : Dream.middleware list;  (** [[@@@use]], around every route. *)
  routes : Route.t list;
  error_handler : Error.handler option;
      (** [[@@@error_handler]], overrides the app's. *)
}
(** A mounted controller: its routes and their description. *)

val v :
  ?middleware:Dream.middleware list ->
  ?error_handler:Error.handler ->
  spec:Spec.t ->
  Route.t list ->
  t

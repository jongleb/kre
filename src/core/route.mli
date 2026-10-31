type handler = Dream.request -> (Dream.response, Error.t) result Lwt.t
(** Answers a matched request or fails with an error the app renders. *)

type t = private {
  verb : Spec.verb;
  middleware : Dream.middleware list;
      (** Handler-level, inside the controller's. *)
  target : handler Routes.route;
}

(** How a handler's value becomes a response. *)
type 'a returns =
  | Unit : unit returns  (** Empty body. *)
  | Text : string returns  (** [text/plain]. *)
  | Json : (module Forge_shared.Json.S with type t = 'a) -> 'a returns
  | Found : (module Forge_shared.Json.S with type t = 'a) -> 'a option returns
      (** [None] answers 404. *)
  | Raw : Dream.response returns

val v :
  ?middleware:Dream.middleware list -> Spec.verb -> handler Routes.route -> t

val handle :
  status:Dream.status ->
  ?guards:unit Guard.t list ->
  'a returns ->
  (Dream.request -> ('a, Error.t) result Lwt.t) ->
  handler

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
  | Redirect : string -> unit returns
      (** [Location] with the route's status. *)

val v :
  ?middleware:Dream.middleware list -> Spec.verb -> handler Routes.route -> t

val handle :
  status:Dream.status ->
  ?guards:unit Guard.t list ->
  ?headers:(string * string) list ->
  ?timeout:float ->
  'a returns ->
  (Dream.request -> ('a, Error.t) result Lwt.t) ->
  handler

val segment :
  (module S : Forge_shared.Scalar.S) ->
  string -> ('a, 'b) Routes.path -> (S.t -> 'a, 'b) Routes.path

val query :
  (module S : Forge_shared.Scalar.S) ->
  (S.t, 'b) Forge_shared.Presence.t ->
  string ->
  Dream.request ->
  ('b, Error.t) result Lwt.t

val body :
  (module J : Forge_shared.Json.S) ->
  Dream.request -> (J.t, Error.t) result Lwt.t

val ok : 'a Lwt.t -> ('a, Error.t) result Lwt.t

(** Sequencing of extractions in generated handlers. *)
module Syntax : sig
  val ( let* ) :
    ('a, Error.t) result Lwt.t ->
    ('a -> ('b, Error.t) result Lwt.t) ->
    ('b, Error.t) result Lwt.t
end

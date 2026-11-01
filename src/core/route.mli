type handler = Dream.request -> (Dream.response, Error.t) result Lwt.t
(** Answers a matched request or fails with an error the app renders. *)

(** Whether a route ends with a wildcard, which must not shadow exact ones. *)
type matching = Exact | Rest

type t = private {
  verb : Spec.verb;
  matching : matching;
  middleware : Dream.middleware list;
      (** Handler-level, inside the controller's. *)
  target : handler Routes.route;
  error_handler : Error.handler option;
      (** [[@@error_handler]], before the controller's and the app's. *)
}

(** How a handler's value becomes a response. *)
type 'a returns =
  | Unit : unit returns  (** Empty body. *)
  | Text : string returns  (** [text/plain]. *)
  | Json : (module Kre_shared.Json.S with type t = 'a) -> 'a returns
  | Found : (module Kre_shared.Json.S with type t = 'a) -> 'a option returns
      (** [None] answers 404. *)
  | Raw : Dream.response returns
  | Redirect : string -> unit returns
      (** [Location] with the route's status. *)

val v :
  ?middleware:Dream.middleware list ->
  ?error_handler:Error.handler ->
  Spec.verb ->
  handler Routes.route ->
  t

val handle :
  status:Dream.status ->
  ?guards:unit Guard.t list ->
  ?headers:(string * string) list ->
  ?timeout:float ->
  ?interceptors:Interceptor.t list ->
  'a returns ->
  (Dream.request -> ('a, Error.t) result Lwt.t) ->
  handler

val events :
  status:Dream.status ->
  ?guards:unit Guard.t list ->
  ?headers:(string * string) list ->
  ?interceptors:Interceptor.t list ->
  (module J : Kre_shared.Json.S) ->
  (Dream.request -> (J.t Lwt_stream.t, Error.t) result Lwt.t) -> handler

val segment :
  (module S : Kre_shared.Scalar.S) ->
  string -> ('a, 'b) Routes.path -> (S.t -> 'a, 'b) Routes.path

val load :
  what:string -> ('id -> 'a option Lwt.t) -> 'id -> ('a, Error.t) result Lwt.t

val query :
  (module S : Kre_shared.Scalar.S) ->
  (S.t, 'b) Kre_shared.Presence.t ->
  string ->
  Dream.request ->
  ('b, Error.t) result Lwt.t

val body :
  (module J : Kre_shared.Json.S) -> Dream.request -> (J.t, Error.t) result Lwt.t

val ok : 'a Lwt.t -> ('a, Error.t) result Lwt.t
val rest : Routes.Parts.t -> string

(** Sequencing of extractions in generated handlers. *)
module Syntax : sig
  val ( let* ) :
    ('a, Error.t) result Lwt.t ->
    ('a -> ('b, Error.t) result Lwt.t) ->
    ('b, Error.t) result Lwt.t
end

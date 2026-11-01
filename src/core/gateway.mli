type socket
(** A connected client of one gateway. *)

type handler
(** Answers one event name; Nest [@SubscribeMessage]. *)

val on :
  string ->
  (module J : Kre_shared.Json.S) ->
  (module R : Kre_shared.Json.S) ->
  (socket -> J.t -> (R.t, Error.t) result Lwt.t) -> handler

val notify :
  string ->
  (module J : Kre_shared.Json.S) ->
  (socket -> J.t -> (unit, Error.t) result Lwt.t) -> handler

val send :
  socket -> event:string -> (module R : Kre_shared.Json.S) -> R.t -> unit Lwt.t

val broadcast :
  socket -> event:string -> (module R : Kre_shared.Json.S) -> R.t -> unit Lwt.t

type t
(** A gateway: its handlers and the clients connected to it. *)

val make : handler list -> t

val connect :
  t -> send:(string -> unit Lwt.t) -> (string -> unit Lwt.t) * (unit -> unit)

val controller : path:string -> t -> Controller.t

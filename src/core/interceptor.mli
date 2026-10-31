type t = {
  around :
    'a.
    Dream.request ->
    (unit -> ('a, Error.t) result Lwt.t) ->
    ('a, Error.t) result Lwt.t;
}
(** Wraps a handler's typed result after guards; Nest interceptors. *)

val logging : t
val timeout : float -> t
val map_error : (Error.t -> Error.t) -> t
val tap : (Dream.request -> unit Lwt.t) -> t
val chain : t list -> t

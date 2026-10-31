(** Live loaders: tables that changed, pushed to the pages that read them. *)

val publish : string list -> unit
val read : string -> unit
val wrote : string -> unit
val deferred : (unit -> ('a, 'e) result Lwt.t) -> ('a, 'e) result Lwt.t
val audit : string list -> Dream.middleware
val subscribe : string list -> string Lwt_stream.t * (unit -> unit)
val controller : Controller.t

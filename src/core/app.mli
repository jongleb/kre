type tls =
  | Development_certificate  (** Dream's built-in localhost certificate. *)
  | Certificate of { certificate_file : string; key_file : string }

type error_handler = Dream.request -> Error.t -> Dream.response Lwt.t

val handler :
  ?middleware:Dream.middleware list ->
  ?error_handler:error_handler ->
  Controller.t list ->
  Dream.handler

val run :
  ?interface:string ->
  ?port:int ->
  ?tls:tls ->
  ?middleware:Dream.middleware list ->
  ?error_handler:error_handler ->
  ?on_start:(unit -> unit Lwt.t) ->
  ?on_shutdown:(unit -> unit Lwt.t) ->
  Controller.t list ->
  unit

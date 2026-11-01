type tls =
  | Development_certificate  (** Dream's built-in localhost certificate. *)
  | Certificate of { certificate_file : string; key_file : string }

val handler :
  ?middleware:Dream.middleware list ->
  ?error_handler:Error.handler ->
  Controller.t list ->
  Dream.handler

val run :
  ?interface:string ->
  ?port:int ->
  ?tls:tls ->
  ?middleware:Dream.middleware list ->
  ?error_handler:Error.handler ->
  ?on_start:(unit -> unit Lwt.t) ->
  ?on_shutdown:(unit -> unit Lwt.t) ->
  ?commands:Command.t list ->
  Controller.t list ->
  unit

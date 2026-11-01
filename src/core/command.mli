type t
(** A command of the application binary: [main.exe seed --count 3]. *)

type args = (string * string) list
(** Options as given: [--count 3] and [--count=3] are both [("count", "3")]. *)

(** What the binary was asked to do. *)
type invocation =
  | Serve  (** No command: start the server. *)
  | Usage of string  (** [help]: the list of commands. *)
  | Run of (unit -> unit Lwt.t)
  | Invalid of string  (** Unknown command or option, or a bad value. *)

val make :
  name:string ->
  doc:string ->
  options:string list ->
  (args -> (unit -> unit Lwt.t, Kre_shared.Validation.t) result) ->
  t

val required :
  (module S : Kre_shared.Scalar.S) ->
  string -> args -> (S.t, Kre_shared.Validation.t) result

val optional :
  (module S : Kre_shared.Scalar.S) ->
  string -> default:S.t -> args -> (S.t, Kre_shared.Validation.t) result

val invoke : t list -> string list -> invocation

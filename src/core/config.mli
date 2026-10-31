type env = string -> string option
(** Looks a variable up: [Sys.getenv_opt], or layers built by [dotenv]. *)

(** Whether a variable must be set, and what the record field holds. *)
type ('a, 'b) presence =
  | Required : ('a, 'a) presence
  | Optional : ('a, 'a option) presence
  | Default : 'a -> ('a, 'a) presence

type 'a field
(** How one record field is read from and shown as an environment variable. *)

val field :
  string -> (module S : Forge_shared.Scalar.S) -> (S.t, 'b) presence -> 'b field

val list :
  string ->
  separator:char ->
  (module S : Forge_shared.Scalar.S) -> (S.t list, 'b) presence -> 'b field

val secret : 'a field -> 'a field
val read : env -> 'a field -> ('a, string list) result
val show : 'a field -> 'a -> string * string
val pp : Format.formatter -> (string * string) list -> unit
val exit_on_error : ('a, string list) result -> 'a
val dotenv : ?env:env -> string list -> env
val profile : ?dir:string -> ?env:env -> unit -> env

(** Applicative composition: [and+] keeps the errors of both sides. *)
module Syntax : sig
  val ( let+ ) :
    ('a, string list) result -> ('a -> 'b) -> ('b, string list) result

  val ( and+ ) :
    ('a, string list) result ->
    ('b, string list) result ->
    ('a * 'b, string list) result
end

module Flag : Forge_shared.Scalar.S with type t = bool
(** [true]/[1]/[yes] and [false]/[0]/[no]. *)

val table : Table.t

type t = private { id : string; owner : string; abilities : string list }
(** A stored API token; the token itself is shown once and never kept. *)

(** API tokens kept in [kre_tokens] by their SHA-256: a provider. *)
module type S = sig
  val issue : owner:string -> abilities:string list -> (string * t) Lwt.t
  val tokens : owner:string -> t list Lwt.t
  val revoke : string -> unit Lwt.t
  val current : t Guard.t
  val ability : string -> t Guard.t
end

module Make (Db : Db.S) : S

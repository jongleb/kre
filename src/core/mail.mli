type t = private {
  from : Forge_shared.Refined.Email.t;
  to_ : Forge_shared.Refined.Email.t;
  cc : Forge_shared.Refined.Email.t list;
  subject : string;
  text : string;
  html : string option;  (** Sent as multipart/alternative next to [text]. *)
}
(** A letter; at least one recipient by construction. *)

val make :
  from:Forge_shared.Refined.Email.t ->
  to_:Forge_shared.Refined.Email.t ->
  ?cc:Forge_shared.Refined.Email.t list ->
  subject:string ->
  text:string ->
  ?html:string ->
  unit ->
  t

val render : t -> string

(** Something that delivers letters: a provider. *)
module type S = sig
  val send : t -> (unit, string) result Lwt.t
end

module Smtp (Config : sig
  val host : string
  val port : int
  val helo : string
end) : S

(** Letters kept in memory, for dev and tests, with a preview page. *)
module Outbox () : sig
  include S

  val sent : unit -> t list
  val controller : Controller.t
end

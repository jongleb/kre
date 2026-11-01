(** Letters to adopters; a stand-in for SMTP that keeps what it sent. *)
module type S = sig
  val sent : unit -> string list
end

include S

val congratulate : Adoption.t -> (unit, string) result Lwt.t

(** The cats provider. *)
module type S = sig
  val add : Create_cat_dto.t -> Cat.t Lwt.t
  val find_all : unit -> Cat.t list Lwt.t
  val find : int -> Cat.t option Lwt.t
end

module Make () : S
(** A provider with its own state; [new CatsService()]. *)

include S

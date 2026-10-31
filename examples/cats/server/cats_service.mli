(** The cats provider: a singleton holding the cats in memory. *)
module type S = sig
  val add : Create_cat_dto.t -> Cat.t Lwt.t
  val find_all : unit -> Cat.t list Lwt.t
  val find : int -> Cat.t option Lwt.t
end

include S

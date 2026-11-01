type 'a t = private {
  items : 'a list;
  page : int;  (** From 1. *)
  size : int;
  total : int;  (** Items on all pages. *)
}
(** One page of a longer list; Spring [Page], Rails kaminari. *)

(** Which page a client asks for: [?page=2&size=20]; a search record. *)
module Request : sig
  type t = private { page : int; size : int }

  include Json.S with type t := t

  val make : page:int -> size:int -> (t, Validation.t) result
  val first : t
  val offset : t -> int
  val codec : t Search.t
end

val make : Request.t -> total:int -> 'a list -> 'a t
val pages : 'a t -> int

(** The JSON of a page of [J.t]: [{"items": […], "page", "size", "total"}]. *)
module Make (J : Json.S) : Json.S with type t = J.t t

val response : ttl:float -> ?clock:(unit -> float) -> unit -> Dream.middleware

type ('k, 'v) memo = {
  find : 'k -> 'v Lwt.t;
  evict : 'k -> unit;  (** Spring [@CacheEvict] for one key. *)
  clear : unit -> unit;  (** [@CacheEvict(allEntries = true)]. *)
}
(** A memoized function with explicit eviction; Spring [@Cacheable]. *)

val memoize :
  ttl:float -> ?clock:(unit -> float) -> ('k -> 'v Lwt.t) -> ('k, 'v) memo

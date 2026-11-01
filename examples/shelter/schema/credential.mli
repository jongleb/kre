type t = private {
  user_id : User.Id.t;
  hash : string;  (** [pbkdf2-sha256$salt$key], both base64url. *)
}
(** A user's password, stored only as a salted PBKDF2 hash. *)

val table : Forge.Table.t
val for_insert : t -> (user_id:int64 -> hash:string -> 'a) -> 'a
val of_row : user_id:int64 -> hash:string -> t
val make : user_id:User.Id.t -> password:string -> t
val verify : t -> password:string -> User.Id.t option

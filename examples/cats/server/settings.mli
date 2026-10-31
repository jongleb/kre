(** The loaded configuration, a singleton provider. *)
module type S = sig
  val config : Config.t
  val database_url : string
end

include S

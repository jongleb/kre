(** The loaded configuration, a singleton provider. *)
module type S = sig
  val config : Config.t
end

include S

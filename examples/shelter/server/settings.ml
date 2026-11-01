module type S = sig
  val config : Config.t
end

let config = Config.load_exn ~env:(Forge.Config.profile ()) ()

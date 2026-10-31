module type S = sig
  val config : Config.t
  val database_url : string
end

let config = Config.load_exn ~env:(Forge.Config.profile ()) ()

let database_url =
  match config.database_url with
  | Some url -> url
  | None ->
      prerr_endline "DATABASE_URL is not set";
      exit 1

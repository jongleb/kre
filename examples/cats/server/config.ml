type t = {
  port : int; [@env "PORT"] [@default 8080]
  debug : bool; [@env "DEBUG"] [@default false]
  origins : string list; [@env "CORS_ORIGINS"] [@sep ","] [@default []]
  session_secret : string; [@env "SESSION_SECRET"] [@secret]
  admin_email : Forge_shared.Refined.Email.t option;
  database_url : string option; [@env "DATABASE_URL"]
  migrations : string; [@default "examples/cats/db/migrations"]
  web : string; [@env "WEB_DIR"] [@default "_build/default/examples/cats/web"]
}
[@@deriving config]

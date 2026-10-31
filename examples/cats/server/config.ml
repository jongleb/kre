type t = {
  port : int; [@env "PORT"] [@default 8080]
  debug : bool; [@env "DEBUG"] [@default false]
  origins : string list; [@env "CORS_ORIGINS"] [@sep ","] [@default []]
  session_secret : string; [@env "SESSION_SECRET"] [@secret]
  admin_email : Forge_shared.Refined.Email.t option;
}
[@@deriving config]

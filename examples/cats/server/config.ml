type t = {
  port : int; [@env "PORT"] [@default 8080]
  debug : bool; [@env "DEBUG"] [@default false]
  origins : string list; [@env "CORS_ORIGINS"] [@sep ","] [@default []]
  session_secret : string; [@env "SESSION_SECRET"] [@secret]
  admin_email : Kre_shared.Refined.Email.t option;
  database_url : string option; [@env "DATABASE_URL"] [@secret]
  web : string;
      [@env "WEB_DIR"]
      [@default Filename.concat (Filename.dirname Sys.executable_name) "../web"]
}
[@@deriving config]

type t = {
  interface : string; [@env "INTERFACE"] [@default "127.0.0.1"]
  port : int; [@env "PORT"] [@default 8080]
  database_url : string; [@env "DATABASE_URL"] [@secret]
  jwt_secret : string; [@env "JWT_SECRET"] [@secret]
  admin_email : Forge_shared.Refined.Email.t option; [@env "ADMIN_EMAIL"]
}
[@@deriving config]

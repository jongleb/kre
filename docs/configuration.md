# Configuration

In Kre the configuration is a record with `[@@deriving config]`. `load` reads all fields and reports all errors at once; `pp` prints the config with secrets hidden.

<!-- $MDX file=../examples/cats/server/config.ml -->
```ocaml
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
```

Profiles: `Kre.Config.profile ()` layers `config/default.env`, then `config/$KRE_ENV.env`, then the real environment; see `bin/main.ml` in [First steps](first-steps.md). The process environment is not changed.

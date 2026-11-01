# Configuration

Nest: `ConfigModule.forRoot` и схема Joi. Kre: запись с `[@@deriving config]`. `load` читает все поля и сообщает все ошибки сразу, `pp` печатает конфиг со скрытыми секретами.

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

Профили (Spring profiles): `Kre.Config.profile ()` накладывает `config/default.env`, затем `config/$KRE_ENV.env`, затем реальное окружение — см. `bin/main.ml` в [First steps](first-steps.md). Окружение процесса не меняется.

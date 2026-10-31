[@@deriving config] reads every field from the environment and prints the
config with secrets hidden.

  $ cat > input.ml <<'ML'
  > type t = {
  >   port : int; [@env "PORT"] [@default 8080]
  >   secret : string; [@secret]
  >   tags : string list; [@sep ","] [@default []]
  >   admin : Email.t option;
  > }
  > [@@deriving config]
  > ML
  $ ./pp.exe -impl input.ml
  type t =
    {
    port: int [@env "PORT"][@default 8080];
    secret: string [@secret ];
    tags: string list [@sep ","][@default []];
    admin: Email.t option }[@@deriving config]
  include
    struct
      let _ = fun (_ : t) -> ()
      let __forge_config_port =
        Forge.Config.field "PORT" (module Forge_shared.Scalar.Int)
          (Forge.Config.Default 8080)
      let _ = __forge_config_port
      let __forge_config_secret =
        Forge.Config.secret
          (Forge.Config.field "SECRET" (module Forge_shared.Scalar.String)
             Forge.Config.Required)
      let _ = __forge_config_secret
      let __forge_config_tags =
        Forge.Config.list "TAGS" ~separator:',' (module
          Forge_shared.Scalar.String) (Forge.Config.Default [])
      let _ = __forge_config_tags
      let __forge_config_admin =
        Forge.Config.field "ADMIN" (module Email) Forge.Config.Optional
      let _ = __forge_config_admin
      let load ?(env= Sys.getenv_opt) () =
        let open Forge.Config.Syntax in
          let+ __forge_port = Forge.Config.read env __forge_config_port
          and+ __forge_secret = Forge.Config.read env __forge_config_secret
          and+ __forge_tags = Forge.Config.read env __forge_config_tags
          and+ __forge_admin = Forge.Config.read env __forge_config_admin in
          {
            port = __forge_port;
            secret = __forge_secret;
            tags = __forge_tags;
            admin = __forge_admin
          }
      let _ = load
      let load_exn ?env () = Forge.Config.exit_on_error (load ?env ())
      let _ = load_exn
      let pp ppf (config : t) =
        Forge.Config.pp ppf
          [Forge.Config.show __forge_config_port config.port;
          Forge.Config.show __forge_config_secret config.secret;
          Forge.Config.show __forge_config_tags config.tags;
          Forge.Config.show __forge_config_admin config.admin]
      let _ = pp
    end[@@ocaml.doc "@inline"][@@merlin.hide ]

An option field has no default.

  $ cat > input.ml <<'ML'
  > type t = { a : int option [@default Some 1] } [@@deriving config]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 1, characters 36-42:
  1 | type t = { a : int option [@default Some 1] } [@@deriving config]
                                          ^^^^^^
  Error: option field a cannot have [@default]: absence is None
  [1]

A list needs a one-character separator.

  $ cat > input.ml <<'ML'
  > type t = { a : string list } [@@deriving config]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 1, characters 11-26:
  1 | type t = { a : string list } [@@deriving config]
                 ^^^^^^^^^^^^^^^
  Error: list field a needs a separator: [@sep ","]
  [1]
  $ cat > input.ml <<'ML'
  > type t = { a : string list [@sep ", "] } [@@deriving config]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 1, characters 33-37:
  1 | type t = { a : string list [@sep ", "] } [@@deriving config]
                                       ^^^^
  Error: [@sep] takes one character, e.g. [@sep ","]
  [1]

Only a record named t.

  $ cat > input.ml <<'ML'
  > type config = { a : int } [@@deriving config]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 1, characters 0-45:
  1 | type config = { a : int } [@@deriving config]
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Error: [@@deriving config] works on one record type named t
  [1]

Unsupported field type.

  $ cat > input.ml <<'ML'
  > type t = { a : int * int } [@@deriving config]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 1, characters 15-24:
  1 | type t = { a : int * int } [@@deriving config]
                     ^^^^^^^^^
  Error: unsupported config type (int * int); use int, int64, float, bool, string, T.t with T : Forge_shared.Scalar.S, an option or a list of those
  [1]

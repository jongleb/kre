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
      let __kre_config_port =
        Kre.Config.field "PORT" (module Kre_shared.Scalar.Int)
          (Kre.Config.Default 8080)
      let _ = __kre_config_port
      let __kre_config_secret =
        Kre.Config.secret
          (Kre.Config.field "SECRET" (module Kre_shared.Scalar.String)
             Kre.Config.Required)
      let _ = __kre_config_secret
      let __kre_config_tags =
        Kre.Config.list "TAGS" ~separator:',' (module Kre_shared.Scalar.String)
          (Kre.Config.Default [])
      let _ = __kre_config_tags
      let __kre_config_admin =
        Kre.Config.field "ADMIN" (module Email) Kre.Config.Optional
      let _ = __kre_config_admin
      let load ?(env= Sys.getenv_opt) () =
        let open Kre.Config.Syntax in
          let+ __kre_port = Kre.Config.read env __kre_config_port
          and+ __kre_secret = Kre.Config.read env __kre_config_secret
          and+ __kre_tags = Kre.Config.read env __kre_config_tags
          and+ __kre_admin = Kre.Config.read env __kre_config_admin in
          {
            port = __kre_port;
            secret = __kre_secret;
            tags = __kre_tags;
            admin = __kre_admin
          }
      let _ = load
      let load_exn ?env () = Kre.Config.exit_on_error (load ?env ())
      let _ = load_exn
      let pairs (config : t) =
        [Kre.Config.show __kre_config_port config.port;
        Kre.Config.show __kre_config_secret config.secret;
        Kre.Config.show __kre_config_tags config.tags;
        Kre.Config.show __kre_config_admin config.admin]
      let _ = pairs
      let pp ppf config = Kre.Config.pp ppf (pairs config)
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
  Error: unsupported config type (int * int); use int, int64, float, bool, string, T.t with T : Kre_shared.Scalar.S, an option or a list of those
  [1]

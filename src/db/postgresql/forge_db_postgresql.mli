(** sqlgg traits: generated query modules are applied to this. *)
module Sql :
  Sqlgg_traits.M_io
    with type 'a connection = Postgresql.connection
     and type 'a IO.future = 'a Lwt.t
     and type Types.Int.t = int64
     and type Types.Text.t = string
     and type Types.Bool.t = bool
     and type Types.Float.t = float

module Driver : Forge.Db.DRIVER with type conn = Postgresql.connection
(** The [Forge.Db] driver: a libpq URL, [postgresql://user:pass@host:port/db].
*)

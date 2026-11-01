module Client : Mariadb.Nonblocking.S with type 'a future = 'a Lwt.t
(** The nonblocking MariaDB client on Lwt. *)

(** sqlgg traits: generated query modules are applied to this. *)
module Sql :
  Sqlgg_traits.M_io
    with type 'a connection = Client.t
     and type 'a IO.future = 'a Lwt.t
     and type Types.Int.t = int64
     and type Types.Text.t = string
     and type Types.Bool.t = bool
     and type Types.Float.t = float

module Driver : Kre.Db.DRIVER with type conn = Client.t
(** The [Kre.Db] driver: [mariadb://user:pass@host:port/db?socket=path]. *)

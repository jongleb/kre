(** What [Make] needs from a database client. *)
module type DRIVER = sig
  type conn

  val connect : string -> conn Lwt.t
  val close : conn -> unit Lwt.t
  val start : conn -> unit Lwt.t
  val commit : conn -> unit Lwt.t
  val rollback : conn -> unit Lwt.t
end

(** A pooled database; services take it as a functor argument. *)
module type S = sig
  type conn

  val with_conn : (conn -> 'a Lwt.t) -> 'a Lwt.t
  val transaction : (conn -> ('a, 'e) result Lwt.t) -> ('a, 'e) result Lwt.t
end

module Make
    (Driver : DRIVER)
    (Config : sig
      val url : string
      val size : int
    end) : S with type conn = Driver.conn

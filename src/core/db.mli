(** What [Make] needs from a database client. *)
module type DRIVER = sig
  type conn

  val connect : string -> conn Lwt.t
  val close : conn -> unit Lwt.t
  val start : conn -> unit Lwt.t
  val commit : conn -> unit Lwt.t
  val rollback : conn -> unit Lwt.t
  val execute : conn -> string -> unit Lwt.t
  val strings : conn -> string -> string list Lwt.t

  val query :
    conn -> string -> string option list -> string option list list Lwt.t
end

(** A pooled database; services take it as a functor argument. *)
module type S = sig
  type conn

  val with_conn : (conn -> 'a Lwt.t) -> 'a Lwt.t
  val transaction : (conn -> ('a, 'e) result Lwt.t) -> ('a, 'e) result Lwt.t
  val query : string -> string option list -> string option list list Lwt.t
  val tx : conn Guard.t

  val within :
    Dream.request ->
    (unit -> ('a, Error.t) result Lwt.t) ->
    ('a, Error.t) result Lwt.t
end

module Make
    (Driver : DRIVER)
    (Config : sig
      val url : string
      val size : int
    end) : S with type conn = Driver.conn

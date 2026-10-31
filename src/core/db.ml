module type DRIVER = sig
  type conn

  val connect : string -> conn Lwt.t
  val close : conn -> unit Lwt.t
  val start : conn -> unit Lwt.t
  val commit : conn -> unit Lwt.t
  val rollback : conn -> unit Lwt.t
  val execute : conn -> string -> unit Lwt.t
  val strings : conn -> string -> string list Lwt.t
end

module type S = sig
  type conn

  val with_conn : (conn -> 'a Lwt.t) -> 'a Lwt.t
  val transaction : (conn -> ('a, 'e) result Lwt.t) -> ('a, 'e) result Lwt.t
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
    end) =
struct
  type conn = Driver.conn

  let pool =
    Lwt_pool.create Config.size ~dispose:Driver.close (fun () ->
        Driver.connect Config.url)

  let with_conn f = Lwt_pool.use pool f

  let transaction f =
    Live.deferred @@ fun () ->
    with_conn (fun conn ->
        let open Lwt.Syntax in
        let* () = Driver.start conn in
        Lwt.try_bind
          (fun () -> f conn)
          (fun result ->
            let+ () =
              match result with
              | Ok _ -> Driver.commit conn
              | Error _ -> Driver.rollback conn
            in
            result)
          (fun exn ->
            let* () = Driver.rollback conn in
            Lwt.reraise exn))

  let field : conn Dream.field = Dream.new_field ~name:"forge.transaction" ()

  let tx =
    Guard.field field
      ~missing:(Error.internal "no open transaction; add [@@transactional]")

  let within request run =
    match Dream.field request field with
    | Some _ ->
        Lwt.return_error
          (Error.internal "nested [@@transactional] is not supported")
    | None ->
        transaction (fun conn ->
            Dream.set_field request field conn;
            run ())
end

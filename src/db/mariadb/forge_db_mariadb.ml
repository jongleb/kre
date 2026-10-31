module Status = Mariadb.Nonblocking.Status

module Client = struct
  type 'a future = 'a Lwt.t

  include Mariadb.Nonblocking.Make (struct
    module IO = struct
      type 'a future = 'a Lwt.t

      let ( >>= ) promise next = Lwt.bind promise next
      let return value = Lwt.return value
    end

    let wait mariadb status =
      let fd = Lwt_unix.of_unix_file_descr (Mariadb.Nonblocking.fd mariadb) in
      let idle = fst (Lwt.task ()) in
      let watch event waiter =
        match event status with true -> waiter fd | false -> idle
      in
      let timeout =
        match (Status.timeout status, Mariadb.Nonblocking.timeout mariadb) with
        | true, 0 -> Lwt.return_unit
        | true, seconds -> Lwt_unix.timeout (float_of_int seconds)
        | false, _ -> idle
      in
      Lwt.catch
        (fun () ->
          Lwt.map
            (fun _ ->
              Status.create ~read:(Lwt_unix.readable fd)
                ~write:(Lwt_unix.writable fd) ())
            (Lwt.nchoose
               [
                 watch Status.read Lwt_unix.wait_read;
                 watch Status.write Lwt_unix.wait_write;
                 timeout;
               ]))
        (function
          | Lwt_unix.Timeout -> Lwt.return (Status.create ~timeout:true ())
          | exn -> Lwt.reraise exn)
  end)
end

module Sql =
  Sqlgg_mariadb.Make
    (struct
      type 'a future = 'a Lwt.t

      let return value = Lwt.return value
      let ( >>= ) promise next = Lwt.bind promise next

      let bracket resource release use =
        Lwt.bind resource (fun resource ->
            Lwt.finalize (fun () -> use resource) (fun () -> release resource))
    end)
    (Client)
    (Sqlgg_mariadb.Default_types (Client))

module Driver = struct
  type conn = Client.t

  let check what = function
    | Ok value -> Lwt.return value
    | Error (code, message) ->
        Lwt.fail_with (Printf.sprintf "mariadb %s: (%d) %s" what code message)

  let connect url =
    let uri = Uri.of_string url in
    let database =
      match String.split_on_char '/' (Uri.path uri) with
      | [ ""; database ] when database <> "" -> Some database
      | _ -> None
    in
    Lwt.bind
      (Client.connect ?host:(Uri.host uri) ?user:(Uri.user uri)
         ?pass:(Uri.password uri) ?db:database ?port:(Uri.port uri)
         ?socket:(Uri.get_query_param uri "socket")
         ())
      (check "connect")

  let close conn = Client.close conn
  let start conn = Lwt.bind (Client.start_txn conn) (check "start transaction")
  let commit conn = Lwt.bind (Client.commit conn) (check "commit")
  let rollback conn = Lwt.bind (Client.rollback conn) (check "rollback")
end

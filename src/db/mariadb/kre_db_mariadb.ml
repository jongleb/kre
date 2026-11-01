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

module Sql = struct
  include
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

  let select conn sql set_params callback =
    Kre.Live.read sql;
    Kre.Profiler.sql sql;
    select conn sql set_params callback

  let select_one conn sql set_params callback =
    Kre.Live.read sql;
    Kre.Profiler.sql sql;
    select_one conn sql set_params callback

  let select_one_maybe conn sql set_params callback =
    Kre.Live.read sql;
    Kre.Profiler.sql sql;
    select_one_maybe conn sql set_params callback

  let execute conn sql set_params =
    Lwt.map
      (fun response ->
        Kre.Live.wrote sql;
        Kre.Profiler.sql sql;
        response)
      (execute conn sql set_params)
end

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

  let run conn ?(params = []) sql consume =
    let open Lwt.Syntax in
    let* statement = Lwt.bind (Client.prepare conn sql) (check sql) in
    let* result =
      Lwt.bind
        (Client.Stmt.execute statement
           (Array.of_list
              (List.map
                 (Option.fold ~none:`Null ~some:(fun text -> `String text))
                 params)))
        (check sql)
    in
    let* value = consume result in
    let+ () = Lwt.bind (Client.Stmt.close statement) (check "close") in
    value

  let execute conn sql = run conn sql (fun _ -> Lwt.return_unit)

  let rows sql cell result =
    let rec fetch collected =
      Lwt.bind
        (Lwt.bind
           (Client.Res.fetch (module Client.Row.Array) result)
           (check sql))
        (function
          | None -> Lwt.return (List.rev collected)
          | Some (row : Client.Field.t array) -> fetch (cell row :: collected))
    in
    fetch []

  let query conn sql params =
    run conn ~params sql
      (match
         String.split_on_char ' '
           (String.lowercase_ascii
              (String.trim (String.map (function '\n' -> ' ' | c -> c) sql)))
       with
      | ("select" | "with") :: _ ->
          rows sql (fun row ->
              Array.to_list
                (Array.map
                   (fun field ->
                     match Client.Field.value field with
                     | `String text -> Some text
                     | `Bytes bytes -> Some (Bytes.to_string bytes)
                     | `Int n -> Some (string_of_int n)
                     | `Int64 n -> Some (Int64.to_string n)
                     | `UInt64 n -> Some (Unsigned.UInt64.to_string n)
                     | `Float f -> Some (Printf.sprintf "%.17g" f)
                     | `Time _ | `Null -> None)
                   row))
      | _ -> fun _ -> Lwt.return [])

  let strings conn sql =
    run conn sql
      (rows sql (fun row ->
           match Client.Field.value row.(0) with
           | `String text -> text
           | `Bytes bytes -> Bytes.to_string bytes
           | `Int n -> string_of_int n
           | `Int64 n -> Int64.to_string n
           | `UInt64 _ | `Float _ | `Time _ | `Null -> ""))
end

let table =
  Table.make ~name:"kre_locks"
    [
      Table.column ~role:Primary "name" (Text (Some 128)) Not_null;
      Table.column "holder" (Text (Some 32)) Not_null;
      Table.column "until" Double Not_null;
    ]

module type S = sig
  val exclusive : ?ttl:float -> string -> (unit -> unit Lwt.t) -> unit Lwt.t
end

module Make (Db : Db.S) = struct
  let exclusive ?(ttl = 600.) name run =
    let holder = Dream.to_base64url (Dream.random 18) in
    let now = Unix.gettimeofday () in
    let seconds value = Printf.sprintf "%.17g" value in
    let open Lwt.Syntax in
    let* () =
      Lwt.catch
        (fun () ->
          Lwt.map ignore
            (Db.query
               "INSERT INTO kre_locks (name, holder, until) VALUES (?, ?, ?)"
               [ Some name; Some holder; Some (seconds (now +. ttl)) ]))
        (fun _ ->
          Lwt.map ignore
            (Db.query
               "UPDATE kre_locks SET holder = ?, until = ? WHERE name = ? AND \
                until < ?"
               [
                 Some holder;
                 Some (seconds (now +. ttl));
                 Some name;
                 Some (seconds now);
               ]))
    in
    let* owner =
      Db.query "SELECT holder FROM kre_locks WHERE name = ?" [ Some name ]
    in
    match owner with
    | [ [ Some current ] ] when String.equal current holder ->
        Lwt.finalize run (fun () ->
            Lwt.map ignore
              (Db.query "DELETE FROM kre_locks WHERE name = ? AND holder = ?"
                 [ Some name; Some holder ]))
    | _ -> Lwt.return_unit
end

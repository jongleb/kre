type t = { version : string; up : string list; down : string list }
type state = Applied | Pending

let parse ~version text =
  let statements lines =
    let finished, pending =
      List.fold_left
        (fun (finished, pending) line ->
          let line = String.trim line in
          if String.ends_with ~suffix:";" line then
            ( String.concat "\n"
                (List.rev
                   (String.sub line 0 (String.length line - 1) :: pending))
              :: finished,
              [] )
          else if line = "" || String.starts_with ~prefix:"--" line then
            (finished, pending)
          else (finished, line :: pending))
        ([], []) lines
    in
    List.rev
      (match pending with
      | [] -> finished
      | pending -> String.concat "\n" (List.rev pending) :: finished)
  in
  let section, up, down =
    List.fold_left
      (fun (section, up, down) line ->
        match (String.trim line, section) with
        | "-- migrate:up", _ -> (`Up, up, down)
        | "-- migrate:down", _ -> (`Down, up, down)
        | _, `Up -> (`Up, line :: up, down)
        | _, `Down -> (`Down, up, line :: down)
        | _, `Header -> (`Header, up, down))
      (`Header, [], [])
      (String.split_on_char '\n' text)
  in
  match (section, statements (List.rev up)) with
  | `Header, _ -> Error (version ^ ": no -- migrate:up section")
  | _, [] -> Error (version ^ ": the up section has no statements")
  | _, up -> Ok { version; up; down = statements (List.rev down) }

let of_files files =
  List.fold_right
    (fun (file, text) loaded ->
      Result.bind loaded (fun loaded ->
          Result.map
            (fun migration -> migration :: loaded)
            (parse ~version:(Filename.remove_extension file) text)))
    (List.sort
       (fun (left, _) (right, _) -> String.compare left right)
       (List.filter (fun (file, _) -> Filename.check_suffix file ".sql") files))
    (Ok [])

let load dir =
  of_files
    (List.map
       (fun file ->
         ( file,
           In_channel.with_open_text (Filename.concat dir file)
             In_channel.input_all ))
       (Array.to_list (Sys.readdir dir)))

let create ~dir name =
  if not (Sys.file_exists dir) then Sys.mkdir dir 0o755;
  let next =
    1
    + List.fold_left
        (fun highest file ->
          match String.split_on_char '_' file with
          | number :: _ ->
              Option.fold ~none:highest ~some:(Int.max highest)
                (int_of_string_opt number)
          | [] -> highest)
        0
        (Array.to_list (Sys.readdir dir))
  in
  let path = Filename.concat dir (Printf.sprintf "%04d_%s.sql" next name) in
  Out_channel.with_open_text path (fun channel ->
      Out_channel.output_string channel "-- migrate:up\n\n-- migrate:down\n");
  path

let applied (type conn) (module D : Db.DRIVER with type conn = conn)
    (conn : conn) =
  let open Lwt.Syntax in
  let* () =
    D.execute conn
      "CREATE TABLE IF NOT EXISTS kre_migrations (version VARCHAR(255) NOT \
       NULL PRIMARY KEY, applied_at TIMESTAMP NOT NULL DEFAULT \
       CURRENT_TIMESTAMP)"
  in
  D.strings conn "SELECT version FROM kre_migrations ORDER BY version"

let status (module D : Db.DRIVER) conn migrations =
  Lwt.map
    (fun applied ->
      List.map
        (fun migration ->
          ( migration,
            Option.fold ~none:Pending
              ~some:(fun _ -> Applied)
              (List.find_opt (String.equal migration.version) applied) ))
        migrations)
    (applied (module D) conn)

let quote version =
  "'" ^ String.concat "''" (String.split_on_char '\'' version) ^ "'"

let up (module D : Db.DRIVER) conn migrations =
  let open Lwt.Syntax in
  let* states = status (module D) conn migrations in
  Lwt_list.filter_map_s
    (fun (migration, state) ->
      match state with
      | Applied -> Lwt.return_none
      | Pending ->
          let* () = Lwt_list.iter_s (D.execute conn) migration.up in
          let+ () =
            D.execute conn
              ("INSERT INTO kre_migrations (version) VALUES ("
             ^ quote migration.version ^ ")")
          in
          Some migration)
    states

let down (module D : Db.DRIVER) conn migrations =
  let open Lwt.Syntax in
  let* states = status (module D) conn migrations in
  match
    List.rev
      (List.filter_map
         (fun (migration, state) ->
           match state with Applied -> Some migration | Pending -> None)
         states)
  with
  | [] -> Lwt.return_none
  | last :: _ ->
      let* () = Lwt_list.iter_s (D.execute conn) last.down in
      let+ () =
        D.execute conn
          ("DELETE FROM kre_migrations WHERE version = " ^ quote last.version)
      in
      Some last

open Cmdliner

let read file =
  match Yojson.Basic.from_file file with
  | `List specs ->
      List.fold_right
        (fun json specs ->
          Result.bind specs (fun specs ->
              Result.map (fun spec -> spec :: specs) (Forge.Spec.of_json json)))
        specs (Ok [])
      |> Result.map_error (fun message -> file ^ ": " ^ message)
  | _ -> Error (file ^ ": expected a JSON array of controller specs")
  | exception Yojson.Json_error message -> Error (file ^ ": " ^ message)

let write out text =
  Out_channel.with_open_text out (fun channel ->
      Out_channel.output_string channel text)

let spec =
  Arg.(
    required
    & opt (some file) None
    & info [ "spec" ] ~docv:"FILE"
        ~doc:"spec.json written by main.exe --emit-spec.")

let out =
  Arg.(
    required
    & opt (some string) None
    & info [ "out" ] ~docv:"FILE" ~doc:"Output file.")

let client =
  let controller =
    Arg.(
      required
      & opt (some string) None
      & info [ "controller" ] ~docv:"PREFIX"
          ~doc:"Controller prefix, e.g. cats.")
  in
  Cmd.v
    (Cmd.info "client" ~doc:"Generate a typed client module for one controller.")
    Term.(
      const (fun file controller out ->
          Result.bind (read file) (fun specs ->
              Option.fold
                ~none:(Error ("no controller with prefix /" ^ controller))
                ~some:(fun spec -> Ok (write out (Generate.client spec)))
                (List.find_opt
                   (fun (spec : Forge.Spec.t) ->
                     String.equal spec.prefix ("/" ^ controller))
                   specs)))
      $ spec $ controller $ out)

let openapi =
  let title =
    Arg.(
      value & opt string "API"
      & info [ "title" ] ~docv:"TITLE" ~doc:"info.title")
  in
  let version =
    Arg.(
      value & opt string "0.0.0"
      & info [ "version" ] ~docv:"VERSION" ~doc:"info.version")
  in
  Cmd.v
    (Cmd.info "openapi"
       ~doc:"Write an OpenAPI 3.1 document for every controller.")
    Term.(
      const (fun file title version out ->
          Result.map
            (fun specs ->
              write out
                (Yojson.Basic.pretty_to_string
                   (Forge.Openapi.document ~title ~version specs)))
            (read file))
      $ spec $ title $ version $ out)

let routes =
  Cmd.v
    (Cmd.info "routes" ~doc:"Print the route table.")
    Term.(
      const (fun file ->
          Result.map
            (fun specs -> print_string (Generate.routes specs))
            (read file))
      $ spec)

let migrate =
  let dir =
    Arg.(
      value & opt string "migrations"
      & info [ "dir" ] ~docv:"DIR" ~doc:"Directory of NNNN_name.sql files.")
  in
  let url =
    Arg.(
      required
      & opt (some string) None
      & info [ "url" ] ~docv:"URL"
          ~env:(Cmd.Env.info "DATABASE_URL")
          ~doc:"mariadb://user:pass@host:port/db")
  in
  let connected run url dir =
    Result.bind (Forge.Migration.load dir) (fun migrations ->
        match
          Lwt_main.run
            (Lwt.bind (Forge_db_mariadb.Driver.connect url) (fun conn ->
                 Lwt.finalize
                   (fun () -> run conn migrations)
                   (fun () -> Forge_db_mariadb.Driver.close conn)))
        with
        | lines -> Ok (List.iter print_endline lines)
        | exception Failure message -> Error message)
  in
  let command name doc run =
    Cmd.v (Cmd.info name ~doc) Term.(const (connected run) $ url $ dir)
  in
  Cmd.group
    (Cmd.info "migrate" ~doc:"Apply, roll back and inspect SQL migrations.")
    [
      command "up" "Apply every pending migration." (fun conn migrations ->
          Lwt.map
            (function
              | [] -> [ "nothing to apply" ]
              | applied ->
                  List.map
                    (fun (migration : Forge.Migration.t) ->
                      "applied " ^ migration.version)
                    applied)
            (Forge.Migration.up
               (module Forge_db_mariadb.Driver)
               conn migrations));
      command "down" "Roll back the last applied migration."
        (fun conn migrations ->
          Lwt.map
            (Option.fold ~none:[ "nothing to roll back" ]
               ~some:(fun (migration : Forge.Migration.t) ->
                 [ "rolled back " ^ migration.version ]))
            (Forge.Migration.down
               (module Forge_db_mariadb.Driver)
               conn migrations));
      command "status" "List migrations and whether they are applied."
        (fun conn migrations ->
          Lwt.map
            (List.map (fun ((migration : Forge.Migration.t), state) ->
                 (match state with
                   | Forge.Migration.Applied -> "applied  "
                   | Forge.Migration.Pending -> "pending  ")
                 ^ migration.version))
            (Forge.Migration.status
               (module Forge_db_mariadb.Driver)
               conn migrations));
      Cmd.v
        (Cmd.info "new" ~doc:"Create the next numbered migration file.")
        Term.(
          const (fun dir name ->
              Ok (print_endline (Forge.Migration.create ~dir name)))
          $ dir
          $ Arg.(required & pos 0 (some string) None & info [] ~docv:"NAME"));
    ]

let () =
  exit
    (Cmd.eval_result
       (Cmd.group
          (Cmd.info "forge" ~doc:"NestJS-style tooling for Forge")
          [ client; openapi; routes; migrate ]))

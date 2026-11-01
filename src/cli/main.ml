open Cmdliner

let read file =
  match Yojson.Basic.from_file file with
  | `List specs ->
      List.fold_right
        (fun json specs ->
          Result.bind specs (fun specs ->
              Result.map (fun spec -> spec :: specs) (Kre.Spec.of_json json)))
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
                   (fun (spec : Kre.Spec.t) ->
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
                   (Kre.Openapi.document ~title ~version specs)))
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
    Result.bind (Kre.Migration.load dir) (fun migrations ->
        match
          Lwt_main.run
            (Lwt.bind (Kre_db_mariadb.Driver.connect url) (fun conn ->
                 Lwt.finalize
                   (fun () -> run conn migrations)
                   (fun () -> Kre_db_mariadb.Driver.close conn)))
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
                    (fun (migration : Kre.Migration.t) ->
                      "applied " ^ migration.version)
                    applied)
            (Kre.Migration.up (module Kre_db_mariadb.Driver) conn migrations));
      command "down" "Roll back the last applied migration."
        (fun conn migrations ->
          Lwt.map
            (Option.fold ~none:[ "nothing to roll back" ]
               ~some:(fun (migration : Kre.Migration.t) ->
                 [ "rolled back " ^ migration.version ]))
            (Kre.Migration.down (module Kre_db_mariadb.Driver) conn migrations));
      command "status" "List migrations and whether they are applied."
        (fun conn migrations ->
          Lwt.map
            (List.map (fun ((migration : Kre.Migration.t), state) ->
                 (match state with
                   | Kre.Migration.Applied -> "applied  "
                   | Kre.Migration.Pending -> "pending  ")
                 ^ migration.version))
            (Kre.Migration.status
               (module Kre_db_mariadb.Driver)
               conn migrations));
      Cmd.v
        (Cmd.info "new" ~doc:"Create the next numbered migration file.")
        Term.(
          const (fun dir name ->
              Ok (print_endline (Kre.Migration.create ~dir name)))
          $ dir
          $ Arg.(required & pos 0 (some string) None & info [] ~docv:"NAME"));
    ]

let scaffold =
  let name = Arg.(required & pos 0 (some string) None & info [] ~docv:"NAME") in
  let report written =
    Result.map
      (fun files ->
        List.iter (fun file -> print_endline ("created " ^ file)) files)
      written
  in
  let generate kind doc =
    Cmd.v
      (Cmd.info
         (match kind with
         | Scaffold.Controller -> "controller"
         | Scaffold.Service -> "service"
         | Scaffold.Dto -> "dto")
         ~doc)
      Term.(
        const (fun name fields -> report (Scaffold.generate kind name ~fields))
        $ name
        $ Arg.(
            value & pos_right 0 string []
            & info [] ~docv:"FIELD"
                ~doc:
                  "A field of the resource, name:type with type string, int, \
                   float, bool or time; the default is name:string."))
  in
  ( Cmd.v
      (Cmd.info "new" ~doc:"Create a project: shared, server, bin and a test.")
      Term.(const (fun name -> report (Scaffold.project name)) $ name),
    Cmd.group
      (Cmd.info "generate" ~doc:"Add a resource, service or DTO to a project.")
      [
        generate Scaffold.Controller
          "A CRUD resource: shared type and DTO, in-memory service, \
           controller, test.";
        generate Scaffold.Service "A service with its module type S.";
        generate Scaffold.Dto "A DTO in shared/.";
      ] )

let () =
  exit
    (Cmd.eval_result
       (Cmd.group
          (Cmd.info "kre" ~doc:"NestJS-style tooling for Kre")
          [ fst scaffold; snd scaffold; client; openapi; routes; migrate ]))

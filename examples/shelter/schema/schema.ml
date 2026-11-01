let () =
  let tables = [ User.table; Cat.table; Adoption.table; Credential.table ] in
  print_string
    (match Sys.argv with
    | [| _; "crud"; name |] ->
        Option.fold ~none:"" ~some:Forge.Table.crud
          (List.find_opt
             (fun (table : Forge.Table.t) -> String.equal table.name name)
             tables)
    | [| _; "migration"; set |] ->
        let tables =
          match set with "jobs" -> [ Forge.Job.table ] | _ -> tables
        in
        String.concat "\n"
          [
            "-- migrate:up";
            Forge.Table.schema Mysql tables;
            "-- migrate:down";
            String.concat ""
              (List.rev_map
                 (fun (table : Forge.Table.t) ->
                   Printf.sprintf "DROP TABLE %s;\n" table.name)
                 tables);
          ]
    | _ -> Forge.Table.schema Mysql tables)

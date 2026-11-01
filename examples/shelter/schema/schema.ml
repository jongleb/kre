let () =
  let tables = [ User.table; Cat.table; Adoption.table; Credential.table ] in
  print_string
    (match Sys.argv with
    | [| _; "crud"; name |] ->
        Option.fold ~none:"" ~some:Kre.Table.crud
          (List.find_opt
             (fun (table : Kre.Table.t) -> String.equal table.name name)
             tables)
    | [| _; "migration"; set |] ->
        let tables =
          match set with
          | "jobs" -> [ Kre.Job.table ]
          | "tokens" -> [ Kre.Token.table ]
          | _ -> tables
        in
        String.concat "\n"
          [
            "-- migrate:up";
            Kre.Table.schema Mysql tables;
            "-- migrate:down";
            String.concat ""
              (List.rev_map
                 (fun (table : Kre.Table.t) ->
                   Printf.sprintf "DROP TABLE %s;\n" table.name)
                 tables);
          ]
    | _ -> Kre.Table.schema Mysql tables)

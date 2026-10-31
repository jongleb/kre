let () =
  print_string
    (match Sys.argv with
    | [| _; "crud" |] -> Forge.Table.crud Cat.table
    | [| _; "postgresql" |] -> Forge.Table.schema Postgresql [ Cat.table ]
    | _ -> Forge.Table.schema Mysql [ Cat.table ])

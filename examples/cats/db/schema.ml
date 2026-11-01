let () =
  print_string
    (match Sys.argv with
    | [| _; "crud" |] -> Kre.Table.crud Cat.table
    | [| _; "postgresql" |] -> Kre.Table.schema Postgresql [ Cat.table ]
    | _ -> Kre.Table.schema Mysql [ Cat.table ])

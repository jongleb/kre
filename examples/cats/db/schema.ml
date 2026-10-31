let () =
  print_string
    (match Sys.argv with
    | [| _; "crud" |] -> Forge.Table.crud Cat.table
    | _ -> Forge.Table.schema [ Cat.table ])

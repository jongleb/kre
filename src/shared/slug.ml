let of_string text =
  String.concat "-"
    (List.filter
       (fun part -> part <> "")
       (String.split_on_char '-'
          (String.map
             (fun c ->
               match Char.lowercase_ascii c with
               | ('a' .. 'z' | '0' .. '9') as kept -> kept
               | _ -> '-')
             text)))

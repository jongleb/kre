let parameters ~pattern host =
  let labels text = String.split_on_char '.' (String.lowercase_ascii text) in
  let host =
    Option.fold ~none:host
      ~some:(fun colon -> String.sub host 0 colon)
      (String.index_opt host ':')
  in
  match List.compare_lengths (labels pattern) (labels host) with
  | 0 ->
      List.fold_left2
        (fun found expected actual ->
          Option.bind found (fun found ->
              match String.split_on_char ':' expected with
              | [ ""; name ] -> Some ((name, actual) :: found)
              | _ when String.equal expected actual -> Some found
              | _ -> None))
        (Some []) (labels pattern) (labels host)
  | _ -> None

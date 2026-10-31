let () =
  let root = Sys.argv.(1) in
  let rec walk relative =
    let absolute = Filename.concat root relative in
    if Sys.is_directory absolute then
      List.concat_map
        (fun child ->
          walk
            (match relative with
            | "" -> child
            | _ -> Filename.concat relative child))
        (List.sort String.compare (Array.to_list (Sys.readdir absolute)))
    else [ (relative, In_channel.with_open_bin absolute In_channel.input_all) ]
  in
  print_string "let files = [\n";
  List.iter
    (fun (path, contents) -> Printf.printf "  (%S, %S);\n" path contents)
    (walk "");
  print_string "]\n"

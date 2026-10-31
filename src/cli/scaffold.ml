type kind = Controller | Service | Dto

let write ~root ~template ~substitutions =
  let replace ~pattern ~by text =
    let length = String.length pattern in
    let buffer = Buffer.create (String.length text) in
    let rec scan index =
      if index >= String.length text then ()
      else if
        index + length <= String.length text
        && String.equal (String.sub text index length) pattern
      then (
        Buffer.add_string buffer by;
        scan (index + length))
      else (
        Buffer.add_char buffer text.[index];
        scan (index + 1))
    in
    scan 0;
    Buffer.contents buffer
  in
  let prefix = template ^ "/" in
  let render text =
    List.fold_left
      (fun text (pattern, by) ->
        replace ~pattern:("{{" ^ pattern ^ "}}") ~by text)
      text substitutions
  in
  let files =
    List.filter_map
      (fun (path, contents) ->
        match path with
        | path when String.starts_with ~prefix path ->
            let relative =
              List.fold_left
                (fun path (pattern, by) -> replace ~pattern ~by path)
                (Filename.remove_extension
                   (String.sub path (String.length prefix)
                      (String.length path - String.length prefix)))
                (List.filter
                   (fun (pattern, _) ->
                     pattern = "plural" || pattern = "singular")
                   substitutions)
            in
            Some (Filename.concat root relative, render contents)
        | _ -> None)
      Templates.files
  in
  match List.find_opt (fun (path, _) -> Sys.file_exists path) files with
  | Some (path, _) -> Error (path ^ " already exists; nothing was written")
  | None ->
      List.iter
        (fun (path, contents) ->
          let rec ensure directory =
            if not (Sys.file_exists directory) then (
              ensure (Filename.dirname directory);
              Sys.mkdir directory 0o755)
          in
          ensure (Filename.dirname path);
          Out_channel.with_open_bin path (fun channel ->
              Out_channel.output_string channel contents))
        files;
      Ok (List.map fst files)

let project name =
  write ~root:name ~template:"new" ~substitutions:[ ("name", name) ]

let generate kind plural =
  let singular =
    if String.ends_with ~suffix:"s" plural then
      String.sub plural 0 (String.length plural - 1)
    else plural
  in
  let substitutions =
    [
      ("plural", plural);
      ("Plural", String.capitalize_ascii plural);
      ("singular", singular);
      ("Singular", String.capitalize_ascii singular);
    ]
  in
  let templates =
    match kind with
    | Controller -> [ "controller"; "service" ]
    | Service -> [ "service" ]
    | Dto -> [ "dto" ]
  in
  List.fold_left
    (fun written template ->
      Result.bind written (fun written ->
          Result.map
            (fun files -> written @ files)
            (write ~root:"." ~template ~substitutions)))
    (Ok []) templates

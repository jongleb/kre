open Ppxlib
open Ast_builder.Default

let root ctxt =
  Filename.concat
    (Filename.dirname
       (Filename.dirname (Expansion_context.Extension.input_name ctxt)))
    "assets"

let rec files directory prefix =
  match Sys.readdir directory with
  | entries ->
      List.concat_map
        (fun entry ->
          let path = Filename.concat directory entry in
          let relative =
            match prefix with "" -> entry | prefix -> prefix ^ "/" ^ entry
          in
          match
            (String.starts_with ~prefix:"." entry, Sys.is_directory path)
          with
          | true, _ -> []
          | false, true -> files path relative
          | false, false -> [ relative ])
        (List.sort String.compare (Array.to_list entries))
  | exception Sys_error _ -> []

let distance a b =
  let previous = Array.init (String.length b + 1) Fun.id in
  String.iteri
    (fun i ca ->
      let diagonal = ref previous.(0) in
      previous.(0) <- i + 1;
      String.iteri
        (fun j cb ->
          let above = previous.(j + 1) in
          previous.(j + 1) <-
            min
              (min (above + 1) (previous.(j) + 1))
              (!diagonal + Bool.to_int (not (Char.equal ca cb)));
          diagonal := above)
        b)
    a;
  previous.(String.length b)

let missing ~loc ~what ~known name =
  let hint =
    Option.fold ~none:""
      ~some:(fun (candidate, _) ->
        Printf.sprintf " (did you mean %S?)" candidate)
      (List.fold_left
         (fun best candidate ->
           let score = distance name candidate in
           match best with
           | Some (_, best_score) when best_score <= score -> best
           | (Some _ | None) when score <= max 2 (String.length name / 3) ->
               Some (candidate, score)
           | Some _ | None -> best)
         None known)
  in
  Location.raise_errorf ~loc
    "%s does not exist%s; add the file and list the folder in \
     (preprocessor_deps (source_tree ../assets))"
    what hint

let asset =
  Extension.V3.declare "asset" Extension.Context.expression
    Ast_pattern.(single_expr_payload (estring __))
    (fun ~ctxt name ->
      let loc = Expansion_context.Extension.extension_point_loc ctxt in
      let root = root ctxt in
      let path = Filename.concat root name in
      match Sys.is_directory path with
      | false ->
          let hash = String.sub (Digest.to_hex (Digest.file path)) 0 8 in
          let directory = Filename.dirname name
          and base = Filename.basename name in
          let hashed =
            match String.rindex_opt base '.' with
            | Some 0 | None -> base ^ "." ^ hash
            | Some dot ->
                String.sub base 0 dot ^ "." ^ hash
                ^ String.sub base dot (String.length base - dot)
          in
          [%expr
            Kre_shared.Asset.checked
              [%e
                estring ~loc
                  ("/assets/"
                  ^
                  match directory with
                  | "." -> hashed
                  | directory -> directory ^ "/" ^ hashed)]]
      | true | (exception Sys_error _) ->
          missing ~loc ~what:("assets/" ^ name) ~known:(files root "") name)

let icon =
  Extension.V3.declare "icon" Extension.Context.expression
    Ast_pattern.(single_expr_payload (estring __))
    (fun ~ctxt name ->
      let loc = Expansion_context.Extension.extension_point_loc ctxt in
      let directory = Filename.concat (root ctxt) "icons" in
      match
        In_channel.with_open_bin
          (Filename.concat directory (name ^ ".svg"))
          In_channel.input_all
      with
      | source -> (
          let rec find index =
            match String.index_from_opt source index '<' with
            | None -> None
            | Some at
              when at + 4 <= String.length source
                   && String.equal (String.sub source at 4) "<svg" ->
                Some at
            | Some at -> find (at + 1)
          in
          match find 0 with
          | Some start ->
              [%expr
                Kre_shared.Icon.checked ~name:[%e estring ~loc name]
                  [%e
                    estring ~loc
                      (String.trim
                         (String.sub source start
                            (String.length source - start)))]]
          | None ->
              Location.raise_errorf ~loc
                "assets/icons/%s.svg is not an SVG: it has no <svg> element"
                name)
      | exception Sys_error _ ->
          missing ~loc
            ~what:(Printf.sprintf "assets/icons/%s.svg" name)
            ~known:
              (List.map Filename.remove_extension
                 (List.filter
                    (fun file -> Filename.check_suffix file ".svg")
                    (files directory "")))
            name)

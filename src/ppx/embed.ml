open Ppxlib
open Ast_builder.Default

let extension =
  Extension.V3.declare "embed_dir" Extension.Context.expression
    Ast_pattern.(single_expr_payload (estring __))
    (fun ~ctxt directory ->
      let loc = Expansion_context.Extension.extension_point_loc ctxt in
      let path =
        Filename.concat
          (Filename.dirname (Expansion_context.Extension.input_name ctxt))
          directory
      in
      match Sys.is_directory path with
      | false | (exception Sys_error _) ->
          Location.raise_errorf ~loc
            "[%%embed_dir %S]: no such directory next to this file; also list \
             it in (preprocessor_deps (glob_files %s/*))"
            directory directory
      | true ->
          elist ~loc
            (List.filter_map
               (fun file ->
                 let full = Filename.concat path file in
                 if String.starts_with ~prefix:"." file || Sys.is_directory full
                 then None
                 else
                   Some
                     [%expr
                       [%e estring ~loc file],
                       [%e
                         estring ~loc
                           (In_channel.with_open_bin full In_channel.input_all)]])
               (List.sort String.compare (Array.to_list (Sys.readdir path)))))

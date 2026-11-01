type args = (string * string) list

type t = {
  name : string;
  doc : string;
  options : string list;
  build : args -> (unit -> unit Lwt.t, Kre_shared.Validation.t) result;
}

type invocation =
  | Serve
  | Usage of string
  | Run of (unit -> unit Lwt.t)
  | Invalid of string

let make ~name ~doc ~options build = { name; doc; options; build }

let parse (module S : Kre_shared.Scalar.S) name raw =
  Result.map_error
    (fun errors ->
      Kre_shared.Validation.fail ~rule:"type"
        (Printf.sprintf "--%s: %s" name
           (String.concat "; "
              (List.map
                 (fun (error : Kre_shared.Validation.error) -> error.message)
                 (Kre_shared.Validation.to_list errors)))))
    (S.of_string raw)

let optional (module S : Kre_shared.Scalar.S) name ~default args =
  Option.fold ~none:(Ok default)
    ~some:(parse (module S) name)
    (List.assoc_opt name args)

let required (module S : Kre_shared.Scalar.S) name args =
  Option.fold
    ~none:
      (Error
         (Kre_shared.Validation.fail ~rule:"required"
            (Printf.sprintf "--%s is required" name)))
    ~some:(parse (module S) name)
    (List.assoc_opt name args)

let invoke commands arguments =
  let usage () =
    String.concat "\n"
      ("commands:"
       :: List.map
            (fun command ->
              Printf.sprintf "  %s%s  %s" command.name
                (String.concat ""
                   (List.map (fun option -> " --" ^ option) command.options))
                command.doc)
            commands
      @ [ "" ])
  in
  let rec options parsed = function
    | [] -> Ok (List.rev parsed)
    | word :: rest when String.starts_with ~prefix:"--" word -> (
        let option = String.sub word 2 (String.length word - 2) in
        match (String.index_opt option '=', rest) with
        | Some at, _ ->
            options
              (( String.sub option 0 at,
                 String.sub option (at + 1) (String.length option - at - 1) )
              :: parsed)
              rest
        | None, value :: rest -> options ((option, value) :: parsed) rest
        | None, [] -> Error (Printf.sprintf "--%s needs a value" option))
    | word :: _ -> Error (Printf.sprintf "unexpected argument %s" word)
  in
  match arguments with
  | [] -> Serve
  | ("help" | "--help") :: _ -> Usage (usage ())
  | name :: rest -> (
      match
        List.find_opt (fun command -> String.equal command.name name) commands
      with
      | None when String.starts_with ~prefix:"--" name -> Serve
      | None ->
          Invalid (Printf.sprintf "unknown command %s\n%s" name (usage ()))
      | Some command -> (
          match options [] rest with
          | Error message -> Invalid message
          | Ok parsed -> (
              match
                List.find_opt
                  (fun (option, _) -> not (List.mem option command.options))
                  parsed
              with
              | Some (option, _) ->
                  Invalid
                    (Printf.sprintf "%s has no option --%s\n%s" name option
                       (usage ()))
              | None ->
                  Result.fold
                    ~ok:(fun run -> Run run)
                    ~error:(fun errors ->
                      Invalid
                        (String.concat "\n"
                           (List.map
                              (fun (error : Kre_shared.Validation.error) ->
                                error.message)
                              (Kre_shared.Validation.to_list errors))))
                    (command.build parsed))))

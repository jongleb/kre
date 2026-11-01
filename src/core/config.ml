type env = string -> string option

type ('a, 'b) presence =
  | Required : ('a, 'a) presence
  | Optional : ('a, 'a option) presence
  | Default : 'a -> ('a, 'a) presence

type visibility = Shown | Hidden

type 'a field = {
  name : string;
  read : env -> ('a, string list) result;
  show : 'a -> string;
  visibility : visibility;
}

let make (type a b) name ~(parse : string -> (a, string) result)
    ~(print : a -> string) (presence : (a, b) presence) : b field =
  let parsed raw =
    Result.map_error
      (fun message -> [ Printf.sprintf "%s: %s: '%s'" name message raw ])
      (parse raw)
  in
  let read env : (b, string list) result =
    match presence with
    | Required ->
        Option.fold ~none:(Error [ name ^ ": missing" ]) ~some:parsed (env name)
    | Optional ->
        Option.fold ~none:(Ok None)
          ~some:(fun raw -> Result.map Option.some (parsed raw))
          (env name)
    | Default value -> Option.fold ~none:(Ok value) ~some:parsed (env name)
  in
  let show : b -> string =
    match presence with
    | Required -> print
    | Default _ -> print
    | Optional -> Option.fold ~none:"" ~some:print
  in
  { name; read; show; visibility = Shown }

let message errors =
  String.concat "; "
    (List.map
       (fun (error : Kre_shared.Validation.error) -> error.message)
       (Kre_shared.Validation.to_list errors))

let field name (module S : Kre_shared.Scalar.S) presence =
  make name
    ~parse:(fun raw -> Result.map_error message (S.of_string raw))
    ~print:S.to_string presence

let list name ~separator (module S : Kre_shared.Scalar.S) presence =
  make name
    ~parse:(fun raw ->
      List.fold_right
        (fun item parsed ->
          Result.bind
            (Result.map_error message (S.of_string (String.trim item)))
            (fun value -> Result.map (List.cons value) parsed))
        (List.filter
           (fun item -> String.trim item <> "")
           (String.split_on_char separator raw))
        (Ok []))
    ~print:(fun values ->
      String.concat (String.make 1 separator) (List.map S.to_string values))
    presence

let secret field = { field with visibility = Hidden }
let read env field = field.read env

let show field value =
  ( field.name,
    match field.visibility with Shown -> field.show value | Hidden -> "***" )

let pp ppf pairs =
  Format.fprintf ppf "@[<v>%a@]"
    (Format.pp_print_list (fun ppf (name, value) ->
         Format.fprintf ppf "%s=%s" name value))
    pairs

let exit_on_error = function
  | Ok config -> config
  | Error errors ->
      List.iter prerr_endline ("configuration errors:" :: errors);
      exit 1

let dotenv ?(env = Sys.getenv_opt) files =
  let after prefix text =
    match String.starts_with ~prefix text with
    | true ->
        Some
          (String.sub text (String.length prefix)
             (String.length text - String.length prefix))
    | false -> None
  in
  let unquote value =
    match String.length value with
    | length
      when length >= 2
           && (value.[0] = '"' || value.[0] = '\'')
           && value.[length - 1] = value.[0] ->
        String.sub value 1 (length - 2)
    | _ -> value
  in
  let variable line =
    let line = String.trim line in
    let line =
      String.trim (Option.value (after "export " line) ~default:line)
    in
    match (after "#" line, String.index_opt line '=') with
    | None, Some equals ->
        Some
          ( String.trim (String.sub line 0 equals),
            unquote
              (String.trim
                 (String.sub line (equals + 1)
                    (String.length line - equals - 1))) )
    | Some _, _ | None, None -> None
  in
  let layers =
    List.rev_map
      (fun file ->
        match In_channel.with_open_text file In_channel.input_lines with
        | lines -> List.filter_map variable lines
        | exception Sys_error _ -> [])
      files
  in
  fun name ->
    match env name with
    | Some value -> Some value
    | None -> List.find_map (List.assoc_opt name) layers

let profile ?(dir = "config") ?(env = Sys.getenv_opt) () =
  dotenv ~env
    [
      Filename.concat dir "default.env";
      Filename.concat dir (Option.value (env "KRE_ENV") ~default:"dev" ^ ".env");
    ]

module Syntax = struct
  let ( let+ ) result f = Result.map f result

  let ( and+ ) left right =
    match (left, right) with
    | Ok left, Ok right -> Ok (left, right)
    | Error errors, Ok _ | Ok _, Error errors -> Error errors
    | Error left, Error right -> Error (left @ right)
end

module Flag = struct
  include Kre_shared.Scalar.Bool

  let of_string raw =
    match String.lowercase_ascii raw with
    | "true" | "1" | "yes" -> Ok true
    | "false" | "0" | "no" -> Ok false
    | _ ->
        Error
          (Kre_shared.Validation.fail ~rule:"type"
             "must be true/1/yes or false/0/no")
end

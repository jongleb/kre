type error = { path : string list; rule : string; message : string }
type t = { first : error; rest : error list }

exception Invalid of t

type 'a rule = { name : string; apply : 'a -> ('a, string) result }

let fail ~rule message = { first = { path = []; rule; message }; rest = [] }

let ok_exn result =
  Result.fold ~ok:Fun.id ~error:(fun errors -> raise (Invalid errors)) result

let to_list { first; rest } = first :: rest

let at prefix { first; rest } =
  let locate error = { error with path = prefix @ error.path } in
  { first = locate first; rest = List.map locate rest }

let to_json errors =
  Jsonkit.declassify
    (`List
       (List.map
          (fun { path; rule; message } ->
            Jsonkit.declassify
              (`Assoc
                 [
                   ( "path",
                     Jsonkit.declassify
                       (`List
                          (List.map
                             (fun segment ->
                               Jsonkit.declassify (`String segment))
                             path)) );
                   ("rule", Jsonkit.declassify (`String rule));
                   ("message", Jsonkit.declassify (`String message));
                 ]))
          (to_list errors)))

let rule ~name apply = { name; apply }

let check rules value =
  let value, failures =
    List.fold_left
      (fun (value, failures) { name; apply } ->
        match apply value with
        | Ok value -> (value, failures)
        | Error message ->
            (value, { path = []; rule = name; message } :: failures))
      (value, []) rules
  in
  match List.rev failures with
  | [] -> Ok value
  | first :: rest -> Error { first; rest }

let field name rules value = Result.map_error (at [ name ]) (check rules value)

module Syntax = struct
  let ( let+ ) result f = Result.map f result

  let ( and+ ) left right =
    match (left, right) with
    | Ok left, Ok right -> Ok (left, right)
    | Error errors, Ok _ | Ok _, Error errors -> Error errors
    | Error left, Error right ->
        Error { left with rest = left.rest @ (right.first :: right.rest) }
end

let min_length n =
  rule ~name:"min_length" (fun s ->
      if Kre_text.length s >= n then Ok s
      else Error (Printf.sprintf "must be at least %d characters" n))

let max_length n =
  rule ~name:"max_length" (fun s ->
      if Kre_text.length s <= n then Ok s
      else Error (Printf.sprintf "must be at most %d characters" n))

let min bound =
  rule ~name:"min" (fun n ->
      if n >= bound then Ok n
      else Error (Printf.sprintf "must be at least %d" bound))

let max bound =
  rule ~name:"max" (fun n ->
      if n <= bound then Ok n
      else Error (Printf.sprintf "must be at most %d" bound))

let range ~min ~max =
  rule ~name:"range" (fun n ->
      if n >= min && n <= max then Ok n
      else Error (Printf.sprintf "must be between %d and %d" min max))

let one_of values =
  rule ~name:"one_of" (fun s ->
      if List.mem s values then Ok s
      else Error ("must be one of: " ^ String.concat ", " values))

let email =
  rule ~name:"email" (fun s ->
      match String.split_on_char '@' s with
      | [ local; domain ]
        when local <> ""
             && (not (String.contains s ' '))
             && List.length (String.split_on_char '.' domain) >= 2
             && not (List.mem "" (String.split_on_char '.' domain)) ->
          Ok s
      | _ -> Error "must be an email address")

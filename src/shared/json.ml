module type S = sig
  type t

  val of_json : Jsonkit.t -> t
  val to_json : t -> Jsonkit.t
  val t_jsonschema : Jsonkit.Jsonschema.t
end

let parse (module J : S) json =
  match J.of_json json with
  | value -> Ok value
  | exception Validation.Invalid errors -> Error errors
  | exception Jsonkit.Of_json_error error ->
      Error
        (Validation.fail ~rule:"type" (Jsonkit.of_json_error_to_string error))

let omit keys json =
  match Jsonkit.classify json with
  | `Assoc fields ->
      Jsonkit.declassify
        (`Assoc
           (Stdlib.List.filter
              (fun (key, _) -> not (Stdlib.List.mem key keys))
              fields))
  | _ -> json

let write_only keys (schema : Jsonkit.Jsonschema.t) : Jsonkit.Jsonschema.t =
  match schema with
  | `Assoc members ->
      `Assoc
        (Stdlib.List.map
           (function
             | "properties", `Assoc properties ->
                 ( "properties",
                   `Assoc
                     (Stdlib.List.map
                        (function
                          | key, `Assoc property when Stdlib.List.mem key keys
                            ->
                              ( key,
                                `Assoc (property @ [ ("writeOnly", `Bool true) ])
                              )
                          | other -> other)
                        properties) )
             | other -> other)
           members)
  | other -> other

module Ignored = struct
  type t = unit

  let of_json (_ : Jsonkit.t) = ()
  let to_json () = Jsonkit.declassify `Null
  let t_jsonschema = `Assoc []
end

module List (J : S) = struct
  type t = J.t list

  let of_json json =
    match Jsonkit.classify json with
    | `List items -> Stdlib.List.map J.of_json items
    | _ ->
        raise
          (Validation.Invalid (Validation.fail ~rule:"type" "must be an array"))

  let to_json items =
    Jsonkit.declassify (`List (Stdlib.List.map J.to_json items))

  let t_jsonschema =
    `Assoc [ ("type", `String "array"); ("items", J.t_jsonschema) ]
end

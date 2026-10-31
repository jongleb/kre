module type S = sig
  type t

  include Json.S with type t := t

  val name : string
  val of_string : string -> (t, Validation.t) result
  val to_string : t -> string
end

let mismatch expected = Validation.fail ~rule:"type" ("must be " ^ expected)
let invalid expected = raise (Validation.Invalid (mismatch expected))

module Int = struct
  type t = int

  let name = "int"

  let of_json json =
    match Jsonkit.classify json with `Int n -> n | _ -> invalid "an integer"

  let to_json n = Jsonkit.declassify (`Int n)
  let t_jsonschema = `Assoc [ ("type", `String "integer") ]

  let of_string s =
    Option.to_result ~none:(mismatch "an integer") (int_of_string_opt s)

  let to_string n = string_of_int n
end

module Int64 = struct
  type t = int64

  let name = "int64"

  let of_string s =
    Option.to_result ~none:(mismatch "a 64-bit integer") (Int64.of_string_opt s)

  let of_json json =
    match Jsonkit.classify json with
    | `String s -> Validation.ok_exn (of_string s)
    | _ -> invalid "a 64-bit integer string"

  let to_string n = Int64.to_string n
  let to_json n = Jsonkit.declassify (`String (Int64.to_string n))

  let t_jsonschema =
    `Assoc [ ("type", `String "string"); ("format", `String "int64") ]
end

module Float = struct
  type t = float

  let name = "float"

  let of_json json =
    match Jsonkit.classify json with
    | `Float f -> f
    | `Int n -> float_of_int n
    | _ -> invalid "a number"

  let to_json f = Jsonkit.declassify (`Float f)
  let t_jsonschema = `Assoc [ ("type", `String "number") ]

  let of_string s =
    Option.to_result ~none:(mismatch "a number") (float_of_string_opt s)

  let to_string f =
    let short = Printf.sprintf "%.15g" f in
    if float_of_string short = f then short else Printf.sprintf "%.17g" f
end

module Bool = struct
  type t = bool

  let name = "bool"

  let of_json json =
    match Jsonkit.classify json with `Bool b -> b | _ -> invalid "a boolean"

  let to_json b = Jsonkit.declassify (`Bool b)
  let t_jsonschema = `Assoc [ ("type", `String "boolean") ]

  let of_string = function
    | "true" -> Ok true
    | "false" -> Ok false
    | _ -> Error (mismatch "true or false")

  let to_string b = string_of_bool b
end

module String = struct
  type t = string

  let name = "string"

  let of_json json =
    match Jsonkit.classify json with `String s -> s | _ -> invalid "a string"

  let to_json s = Jsonkit.declassify (`String s)
  let t_jsonschema = `Assoc [ ("type", `String "string") ]
  let of_string s = Ok s
  let to_string s = s
end

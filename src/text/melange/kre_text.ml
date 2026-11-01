external code_points : string -> string array = "from" [@@mel.scope "Array"]

let length text = Array.length (code_points text)

module Pattern = struct
  type t = Js.Re.t

  let of_string source =
    match Js.Re.fromString source with
    | pattern -> Ok pattern
    | exception _ -> Error "it does not parse"

  let matching pattern text =
    Option.map (fun _ -> text) (Js.Re.exec ~str:text pattern)
end

let length text =
  String.fold_left
    (fun total byte ->
      match Char.code byte land 0xC0 with 0x80 -> total | _ -> total + 1)
    0 text

module Pattern = struct
  type t = Re.re

  let of_string source =
    match Re.Perl.compile_pat source with
    | pattern -> Ok pattern
    | exception Re.Perl.Parse_error -> Error "it does not parse"
    | exception Re.Perl.Not_supported ->
        Error "it uses syntax the server cannot run"

  let matching pattern text =
    Option.map (fun _ -> text) (Re.exec_opt pattern text)
end

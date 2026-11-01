let sign ~secret text =
  Digestif.SHA256.to_hex (Digestif.SHA256.hmac_string ~key:secret text)

let url ?(now = Unix.gettimeofday ()) ~secret ~expires_in target =
  let unsigned =
    Printf.sprintf "%s%sexpires=%d" target
      (match String.index_opt target '?' with Some _ -> "&" | None -> "?")
      (int_of_float (now +. expires_in))
  in
  unsigned ^ "&signature=" ^ sign ~secret unsigned

let guard ?(now = Unix.gettimeofday) ~secret () request =
  let target = Dream.target request in
  let refused = Error.forbidden "this link is invalid or has expired" in
  Lwt.return
    (match
       ( Option.bind (String.rindex_opt target '&') (fun at ->
             match
               String.split_on_char '='
                 (String.sub target (at + 1) (String.length target - at - 1))
             with
             | [ "signature"; signature ] ->
                 Some (String.sub target 0 at, signature)
             | _ -> None),
         Option.bind (Dream.query request "expires") float_of_string_opt )
     with
    | Some (unsigned, signature), Some expires
      when Eqaf.equal signature (sign ~secret unsigned) && now () < expires ->
        Ok ()
    | _ -> Error refused)

type claims = {
  subject : string;
  expires : float;
  extra : (string * Jsonkit.t) list;
}

type error = Malformed | Bad_signature | Expired

let signature ~secret message =
  Dream.to_base64url
    (Digestif.SHA256.to_raw_string
       (Digestif.SHA256.hmac_string ~key:secret message))

let sign ~secret ?(now = Unix.gettimeofday ()) ?(extra = []) ~expires_in subject
    =
  let payload =
    Dream.to_base64url
      (Yojson.Basic.to_string
         (`Assoc
            ([
               ("sub", `String subject);
               ("exp", `Int (int_of_float (now +. expires_in)));
             ]
            @ extra)))
  in
  let message =
    Dream.to_base64url {|{"alg":"HS256","typ":"JWT"}|} ^ "." ^ payload
  in
  message ^ "." ^ signature ~secret message

let verify ~secret ?(now = Unix.gettimeofday ()) token =
  match String.split_on_char '.' token with
  | [ header; payload; signed ]
    when Eqaf.equal signed (signature ~secret (header ^ "." ^ payload)) -> (
      match
        Option.map Yojson.Basic.from_string (Dream.from_base64url payload)
      with
      | Some (`Assoc members) -> (
          match
            (List.assoc_opt "sub" members, List.assoc_opt "exp" members)
          with
          | Some (`String subject), Some (`Int expires)
            when now < float_of_int expires ->
              Ok
                {
                  subject;
                  expires = float_of_int expires;
                  extra =
                    List.filter
                      (fun (name, _) -> name <> "sub" && name <> "exp")
                      members;
                }
          | Some (`String _), Some (`Int _) -> Error (`Jwt Expired)
          | _ -> Error (`Jwt Malformed))
      | Some _ | None -> Error (`Jwt Malformed)
      | exception Yojson.Json_error _ -> Error (`Jwt Malformed))
  | [ _; _; _ ] -> Error (`Jwt Bad_signature)
  | _ -> Error (`Jwt Malformed)

let bearer ~secret request =
  Lwt.return
    (match Dream.header request "Authorization" with
    | Some authorization when String.starts_with ~prefix:"Bearer " authorization
      ->
        Result.map_error
          (fun (`Jwt error) ->
            Error.unauthorized
              (match error with
              | Malformed -> "malformed token"
              | Bad_signature -> "bad token signature"
              | Expired -> "token expired"))
          (verify ~secret
             (String.sub authorization 7 (String.length authorization - 7)))
    | Some _ | None -> Error (Error.unauthorized "missing bearer token"))

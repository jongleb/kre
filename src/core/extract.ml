let req request = Lwt.return_ok request

let ip request =
  let client = Dream.client request in
  Lwt.return_ok
    (Option.fold ~none:client
       ~some:(fun colon -> String.sub client 0 colon)
       (String.rindex_opt client ':'))

let host request =
  Lwt.return
    (Option.to_result
       ~none:(Error.bad_request "missing Host header")
       (Dream.header request "Host"))

let headers request = Lwt.return_ok (Dream.all_headers request)
let queries request = Lwt.return_ok (Dream.all_queries request)
let cookies request = Lwt.return_ok (Dream.all_cookies request)

let lookup (type b) (module S : Forge_shared.Scalar.S)
    (presence : (S.t, b) Forge_shared.Presence.t) ~what ~missing name values :
    (b, Error.t) result =
  let parse raw =
    Result.map_error
      (fun errors ->
        Error.bad_request
          ~extensions:
            [
              ( "errors",
                Forge_shared.Validation.to_json
                  (Forge_shared.Validation.at [ name ] errors) );
            ]
          (Printf.sprintf "invalid %s %s" what name))
      (S.of_string raw)
  in
  match presence with
  | Required -> (
      match values with raw :: _ -> parse raw | [] -> Error missing)
  | Optional -> (
      match values with
      | raw :: _ -> Result.map Option.some (parse raw)
      | [] -> Ok None)
  | Repeated ->
      List.fold_right
        (fun raw parsed ->
          Result.bind (parse raw) (fun value ->
              Result.map (List.cons value) parsed))
        values (Ok [])

let header (module S : Forge_shared.Scalar.S) presence name request =
  Lwt.return
    (lookup
       (module S)
       presence ~what:"header" name
       ~missing:(Error.bad_request ("missing header " ^ name))
       (Dream.headers request name))

let cookie (module S : Forge_shared.Scalar.S) presence name request =
  Lwt.return
    (lookup
       (module S)
       presence ~what:"cookie" name
       ~missing:(Error.bad_request ("missing cookie " ^ name))
       (Option.to_list (Dream.cookie ~decrypt:false request name)))

let signed_cookie (module S : Forge_shared.Scalar.S) presence name request =
  Lwt.return
    (lookup
       (module S)
       presence ~what:"signed cookie" name
       ~missing:(Error.unauthorized ("missing signed cookie " ^ name))
       (Option.to_list (Dream.cookie request name)))

let session (module S : Forge_shared.Scalar.S) presence name request =
  Lwt.return
    (lookup
       (module S)
       presence ~what:"session field" name
       ~missing:(Error.unauthorized ("not signed in: no session field " ^ name))
       (Option.to_list (Dream.session_field request name)))

let body_field (module J : Forge_shared.Json.S) name request =
  Lwt.map
    (fun text ->
      match Jsonkit.classify (Jsonkit.of_string text) with
      | `Assoc fields ->
          Option.fold
            ~none:
              (Error
                 (Error.unprocessable
                    (Forge_shared.Validation.at [ name ]
                       (Forge_shared.Validation.fail ~rule:"missing" "required"))))
            ~some:(fun json ->
              Result.map_error
                (fun errors ->
                  Error.unprocessable
                    (Forge_shared.Validation.at [ name ] errors))
                (Forge_shared.Json.parse (module J) json))
            (List.assoc_opt name fields)
      | _ ->
          Error
            (Error.unprocessable
               (Forge_shared.Validation.fail ~rule:"type"
                  "body must be an object"))
      | exception Jsonkit.Of_string_error message ->
          Error (Error.bad_request ("request body is not JSON: " ^ message)))
    (Dream.body request)

let host_param ~pattern name request =
  Lwt.return
    (Option.to_result
       ~none:(Error.bad_request ("host does not match " ^ pattern))
       (Option.bind
          (Host.parameters ~pattern
             (Option.value (Dream.header request "Host") ~default:""))
          (List.assoc_opt name)))

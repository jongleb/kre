type origins = Any | Only of string list
type credentials = Include | Omit

let middleware ?(origins = Any)
    ?(methods = [ "GET"; "POST"; "PUT"; "PATCH"; "DELETE" ])
    ?(headers = [ "Content-Type"; "Authorization" ]) ?(credentials = Omit)
    ?(max_age = 600) () : Dream.middleware =
 fun next request ->
  let allowed =
    Option.bind (Dream.header request "Origin") (fun origin ->
        match (origins, credentials) with
        | Any, Omit -> Some "*"
        | Any, Include -> Some origin
        | Only listed, _ -> List.find_opt (String.equal origin) listed)
  in
  let cors_headers =
    Option.fold ~none:[]
      ~some:(fun origin ->
        ("Access-Control-Allow-Origin", origin)
        :: ("Vary", "Origin")
        ::
        (match credentials with
        | Include -> [ ("Access-Control-Allow-Credentials", "true") ]
        | Omit -> []))
      allowed
  in
  match
    (Dream.method_ request, Dream.header request "Access-Control-Request-Method")
  with
  | `OPTIONS, Some _ ->
      Dream.empty `No_Content
        ~headers:
          (cors_headers
          @ Option.fold ~none:[]
              ~some:(fun _ ->
                [
                  ("Access-Control-Allow-Methods", String.concat ", " methods);
                  ("Access-Control-Allow-Headers", String.concat ", " headers);
                  ("Access-Control-Max-Age", string_of_int max_age);
                ])
              allowed)
  | _ ->
      Lwt.map
        (fun response ->
          List.iter
            (fun (name, value) -> Dream.add_header response name value)
            cors_headers;
          response)
        (next request)

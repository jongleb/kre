type transport = Https_only of { max_age : int } | Any_transport

let middleware ?(content_security_policy = "default-src 'self'")
    ?(transport = Any_transport) () : Dream.middleware =
 fun next request ->
  Lwt.map
    (fun response ->
      List.iter
        (fun (name, value) ->
          match Dream.header response name with
          | Some _ -> ()
          | None -> Dream.add_header response name value)
        ([
           ("Content-Security-Policy", content_security_policy);
           ("X-Content-Type-Options", "nosniff");
           ("X-Frame-Options", "DENY");
           ("Referrer-Policy", "no-referrer");
           ("Cross-Origin-Opener-Policy", "same-origin");
         ]
        @
        match transport with
        | Https_only { max_age } ->
            [
              ( "Strict-Transport-Security",
                Printf.sprintf "max-age=%d; includeSubDomains" max_age );
            ]
        | Any_transport -> []);
      response)
    (next request)

let middleware next request =
  Lwt.bind (next request) (fun response ->
      match
        ( Dream.method_ request,
          Dream.status response,
          Dream.header response "Content-Type" )
      with
      | _, _, Some "text/event-stream" -> Lwt.return response
      | (`GET | `HEAD), `OK, _ ->
          Lwt.map
            (fun body ->
              let tag =
                Printf.sprintf "\"%s\""
                  (Digest.BLAKE128.to_hex (Digest.BLAKE128.string body))
              in
              match
                Option.bind (Dream.header request "If-None-Match")
                  (fun header ->
                    List.find_opt
                      (fun candidate ->
                        List.mem (String.trim candidate)
                          [ tag; "W/" ^ tag; "*" ])
                      (String.split_on_char ',' header))
              with
              | Some _ ->
                  Dream.response ~status:`Not_Modified
                    ~headers:[ ("ETag", tag) ]
                    ""
              | None ->
                  Dream.set_header response "ETag" tag;
                  response)
            (Dream.body response)
      | _ -> Lwt.return response)

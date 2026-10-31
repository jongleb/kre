let use ~dir : Dream.middleware =
 fun next request ->
  let path, _ = Dream.split_target (Dream.target request) in
  match
    ( Dream.method_ request,
      String.split_on_char '/' path,
      Dream.header request "Accept" )
  with
  | `GET, "" :: "static" :: rest, _ when not (List.mem ".." rest) ->
      Dream.from_filesystem (Filename.concat dir "js") (String.concat "/" rest)
        request
  | `GET, _, Some accept when String.starts_with ~prefix:"text/html" accept ->
      Dream.from_filesystem dir "page.html" request
  | _ -> next request

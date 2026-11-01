let middleware ~dir next request =
  match
    ( Dream.method_ request,
      String.split_on_char '/' (fst (Dream.split_target (Dream.target request)))
    )
  with
  | (`GET | `HEAD), "" :: "assets" :: (_ :: _ as segments)
    when not
           (List.exists
              (fun segment -> List.mem segment [ ""; "."; ".." ])
              segments) -> (
      let hashed = List.nth segments (List.length segments - 1) in
      let original, hash =
        match List.rev (String.split_on_char '.' hashed) with
        | extension :: hash :: (_ :: _ as base) ->
            (String.concat "." (List.rev base) ^ "." ^ extension, hash)
        | hash :: (_ :: _ as base) -> (String.concat "." (List.rev base), hash)
        | _ -> (hashed, "")
      in
      let relative =
        String.concat "/"
          (List.filteri
             (fun index _ -> index < List.length segments - 1)
             segments
          @ [ original ])
      in
      let path = Filename.concat dir relative in
      match String.sub (Digest.to_hex (Digest.file path)) 0 8 with
      | current when String.equal current hash ->
          Lwt.map
            (fun response ->
              Dream.set_header response "Cache-Control"
                "public, max-age=31536000, immutable";
              response)
            (Dream.from_filesystem dir relative request)
      | _ -> next request
      | exception Sys_error _ -> next request)
  | _ -> next request

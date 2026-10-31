type window = { started : float; count : int }

let middleware ~limit ~window
    ?(key =
      fun request ->
        let client = Dream.client request in
        Option.fold ~none:client
          ~some:(fun colon -> String.sub client 0 colon)
          (String.rindex_opt client ':')) ?(clock = Unix.gettimeofday) () :
    Dream.middleware =
  let windows : (string, window) Hashtbl.t = Hashtbl.create 1024 in
  fun next request ->
    let now = clock () in
    let client = key request in
    let current =
      match Hashtbl.find_opt windows client with
      | Some current when now -. current.started < window ->
          { current with count = current.count + 1 }
      | Some _ | None -> { started = now; count = 1 }
    in
    if Hashtbl.length windows > 100_000 then
      Hashtbl.filter_map_inplace
        (fun _ (kept : window) ->
          if now -. kept.started < window then Some kept else None)
        windows;
    Hashtbl.replace windows client current;
    match current.count with
    | count when count > limit ->
        Lwt.map
          (fun response ->
            Dream.add_header response "Retry-After"
              (string_of_int
                 (int_of_float (ceil (current.started +. window -. now))));
            response)
          (Error.to_response request
             (Error.make ~status:`Too_Many_Requests ~code:"rate_limited"
                (Printf.sprintf "more than %d requests in %gs" limit window)))
    | _ -> next request

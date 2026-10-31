type stored = {
  expires : float;
  status : Dream.status;
  headers : (string * string) list;
  body : string;
}

let response ~ttl ?(clock = Unix.gettimeofday) () : Dream.middleware =
  let entries : (string, stored) Hashtbl.t = Hashtbl.create 64 in
  fun next request ->
    let key = Dream.target request in
    match Hashtbl.find_opt entries key with
    | Some stored when clock () < stored.expires ->
        Lwt.return
          (Dream.response ~status:stored.status
             ~headers:(("X-Cache", "hit") :: stored.headers)
             stored.body)
    | Some _ | None ->
        Lwt.bind (next request) (fun response ->
            match
              (Dream.status response, Dream.header response "Content-Type")
            with
            | `OK, content_type when content_type <> Some "text/event-stream" ->
                Lwt.map
                  (fun body ->
                    let headers = Dream.all_headers response in
                    Hashtbl.replace entries key
                      { expires = clock () +. ttl; status = `OK; headers; body };
                    Dream.response ~status:`OK
                      ~headers:(("X-Cache", "miss") :: headers)
                      body)
                  (Dream.body response)
            | _ -> Lwt.return response)

type ('k, 'v) memo = {
  find : 'k -> 'v Lwt.t;
  evict : 'k -> unit;
  clear : unit -> unit;
}

let memoize ~ttl ?(clock = Unix.gettimeofday) f =
  let entries = Hashtbl.create 64 in
  {
    find =
      (fun key ->
        match Hashtbl.find_opt entries key with
        | Some (expires, value) when clock () < expires -> Lwt.return value
        | Some _ | None ->
            Lwt.map
              (fun value ->
                Hashtbl.replace entries key (clock () +. ttl, value);
                value)
              (f key));
    evict = (fun key -> Hashtbl.remove entries key);
    clear = (fun () -> Hashtbl.reset entries);
  }

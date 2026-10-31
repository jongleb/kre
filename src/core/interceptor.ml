type t = {
  around :
    'a.
    Dream.request ->
    (unit -> ('a, Error.t) result Lwt.t) ->
    ('a, Error.t) result Lwt.t;
}

let logging =
  {
    around =
      (fun request next ->
        let started = Unix.gettimeofday () in
        Lwt.map
          (fun result ->
            Dream.info (fun log ->
                log ~request "%s %s: %s in %.1fms"
                  (Dream.method_to_string (Dream.method_ request))
                  (Dream.target request)
                  (Result.fold
                     ~ok:(fun _ -> "ok")
                     ~error:(fun (error : Error.t) -> error.code)
                     result)
                  ((Unix.gettimeofday () -. started) *. 1000.));
            result)
          (next ()));
  }

let timeout seconds =
  {
    around =
      (fun _ next ->
        Lwt.pick
          [
            next ();
            Lwt.map
              (fun () ->
                Error
                  (Error.make ~status:`Gateway_Timeout ~code:"timeout"
                     (Printf.sprintf "handler took longer than %gs" seconds)))
              (Lwt_unix.sleep seconds);
          ]);
  }

let map_error f =
  { around = (fun _ next -> Lwt.map (Result.map_error f) (next ())) }

let tap f =
  { around = (fun request next -> Lwt.bind (f request) (fun () -> next ())) }

let chain interceptors =
  {
    around =
      (fun request next ->
        List.fold_right
          (fun interceptor next () -> interceptor.around request next)
          interceptors next ());
  }

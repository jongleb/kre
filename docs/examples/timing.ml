let use : Dream.middleware =
 fun next request ->
  let started = Unix.gettimeofday () in
  Lwt.map
    (fun response ->
      Dream.add_header response "Server-Timing"
        (Printf.sprintf "app;dur=%.1f"
           ((Unix.gettimeofday () -. started) *. 1000.));
      response)
    (next request)

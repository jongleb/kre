type timing = Every of float | After of float | Cron of Forge_shared.Cron.t
type job = { name : string; timing : timing; run : unit -> unit Lwt.t }

let job ~name timing run = { name; timing; run }

let start jobs =
  let open Lwt.Syntax in
  let attempt job =
    Lwt.catch job.run (fun exn ->
        Dream.error (fun log ->
            log "job %s failed: %s" job.name (Printexc.to_string exn));
        Lwt.return_unit)
  in
  let rec every seconds job =
    let* () = Lwt_unix.sleep seconds in
    let* () = attempt job in
    every seconds job
  in
  let rec cron schedule job =
    let now = Unix.gettimeofday () in
    match Forge_shared.Cron.next schedule ~after:now with
    | None -> Lwt.return_unit
    | Some at ->
        let* () = Lwt_unix.sleep (at -. now) in
        let* () = attempt job in
        cron schedule job
  in
  let running =
    List.map
      (fun job ->
        match job.timing with
        | Every seconds -> every seconds job
        | After seconds ->
            Lwt.bind (Lwt_unix.sleep seconds) (fun () -> attempt job)
        | Cron schedule -> cron schedule job)
      jobs
  in
  fun () ->
    List.iter Lwt.cancel running;
    Lwt.return_unit

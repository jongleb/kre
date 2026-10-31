type t = {
  controllers : Controller.t list;
  on_start : unit -> unit Lwt.t;
  on_shutdown : unit -> unit Lwt.t;
}

let make ~controllers ~on_start ~on_shutdown ?(jobs = []) () =
  let sequence hooks () = Lwt_list.iter_s (fun hook -> hook ()) hooks in
  let stop = ref (fun () -> Lwt.return_unit) in
  {
    controllers;
    on_start =
      (fun () ->
        Lwt.map (fun () -> stop := Schedule.start jobs) (sequence on_start ()));
    on_shutdown =
      (fun () -> Lwt.bind (!stop ()) (sequence (List.rev on_shutdown)));
  }

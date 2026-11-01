type t = {
  controllers : Controller.t list;
  on_start : unit -> unit Lwt.t;
  on_shutdown : unit -> unit Lwt.t;
  health : Actuator.check list;
  commands : Command.t list;
  beans : Actuator.bean list;
}

let make ~controllers ~on_start ~on_shutdown ?(jobs = []) ?(health = [])
    ?(commands = []) ?(beans = []) () =
  let sequence hooks () = Lwt_list.iter_s (fun hook -> hook ()) hooks in
  let stop = ref (fun () -> Lwt.return_unit) in
  {
    controllers;
    health;
    commands;
    beans;
    on_start =
      (fun () ->
        Lwt.map (fun () -> stop := Schedule.start jobs) (sequence on_start ()));
    on_shutdown =
      (fun () -> Lwt.bind (!stop ()) (sequence (List.rev on_shutdown)));
  }

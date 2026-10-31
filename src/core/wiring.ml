type t = {
  controllers : Controller.t list;
  on_start : unit -> unit Lwt.t;
  on_shutdown : unit -> unit Lwt.t;
}

let make ~controllers ~on_start ~on_shutdown =
  let sequence hooks () = Lwt_list.iter_s (fun hook -> hook ()) hooks in
  {
    controllers;
    on_start = sequence on_start;
    on_shutdown = sequence (List.rev on_shutdown);
  }

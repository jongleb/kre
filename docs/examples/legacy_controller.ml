[@@@controller "legacy"]
[@@@error_handler Error_pages.handler]

let old_cats () : unit Lwt.t = Lwt.return_unit
[@@get "cats"] [@@redirect "/cats"]

let slow () : string Lwt.t =
  let%lwt () = Lwt_unix.sleep 1.0 in
  Lwt.return "late"
[@@get "slow"] [@@timeout 0.05]

let fresh () : string Lwt.t = Lwt.return "fresh"
[@@get "fresh"] [@@header "Cache-Control", "no-store"]

let gone () : (unit, Forge.Error.t) result Lwt.t =
  Lwt.return_error (Forge.Error.not_found "gone")
[@@get "gone"]

let status () : string Lwt.t = Lwt.return "v2" [@@get "status"] [@@version 2]

let plain () : (unit, Forge.Error.t) result Lwt.t =
  Lwt.return_error (Forge.Error.not_found "plain")
[@@get "plain"] [@@error_handler Forge.Error.to_response]

[@@@controller "downloads"]

let secret = "change-me"

let link ~(id : int) () : string Lwt.t =
  Lwt.return
    (Kre.Signed.url ~secret ~expires_in:3600.
       ("/downloads/" ^ string_of_int id))
[@@get ":id/link"]

let file ~(id : int) () : string Lwt.t =
  Lwt.return (Printf.sprintf "file %d" id)
[@@get ":id"] [@@signed secret]

[@@@controller "files"]

let download ~(path : (string[@wildcard])) () : string Lwt.t =
  Lwt.return ("file " ^ path)
[@@get "*"]

let probe () : unit Lwt.t = Lwt.return_unit [@@options "probe"]

let echo (request : Dream.request) () : string Lwt.t =
  Lwt.return (Dream.method_to_string (Dream.method_ request))
[@@all "echo"]

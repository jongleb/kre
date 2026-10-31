[@@@controller "whoami"]

let show (client : (string[@from Decorators.client]))
    ~(language : (string[@from Decorators.language])) () : string Lwt.t =
  Lwt.return (client ^ " " ^ language)
[@@get]

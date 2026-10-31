[@@@controller "admin"]
[@@@guards [ Roles.signed_in ]]

let purge (module Cats : Cats_service.S)
    ~admin:(_ : (Roles.Admin.t[@guard Roles.admin])) () : unit Lwt.t =
  Lwt.map ignore (Cats.find_all ())
[@@delete "cats"]

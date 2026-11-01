[@@@controller "members"]

let ann : Member.t =
  { id = 1; name = "Ann"; email = Some "ann@x.io"; notes = Some "pays late" }

let find () : Member.t Lwt.t = Lwt.return ann [@@get]
let me () : (Member.t[@view "owner"]) Lwt.t = Lwt.return ann [@@get "me"]

let audit () : (Member.t[@view "admin"]) list Lwt.t = Lwt.return [ ann ]
[@@get "audit"]

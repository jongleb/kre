[@@@controller "uploads"]

let avatar ~(file : (Kre.Upload.t[@file "avatar"]))
    ~(title : (string[@form "title"])) ~(tags : (string list[@form "tag"])) () :
    string Lwt.t =
  Lwt.return
    (Printf.sprintf "%s: %s, %d bytes, tags %s" title
       (Option.value file.filename ~default:"-")
       (String.length file.content)
       (String.concat "," tags))
[@@post "avatar"]

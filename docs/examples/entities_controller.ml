[@@@controller "entities"]

let update ~(id : int) ~(entity : (Profile.t[@body]))
    ~(client_name : (string[@header "X-Client-Name"]))
    ~(trace : (string option[@header "X-Trace"]))
    ~(theme : (string option[@cookie "theme"]))
    ~(page_size : (int[@query "page-size"])) (ip : (string[@ip])) () :
    string Lwt.t =
  Lwt.return
    (String.concat " "
       [
         string_of_int id;
         entity.display_name;
         client_name;
         Option.value trace ~default:"-";
         Option.value theme ~default:"-";
         string_of_int page_size;
         ip;
       ])
[@@put ":id"]

let rename ~(cat_id : (int[@param "id"])) ~(name : (Cat.Name.t[@body "name"])) :
    string Lwt.t =
  Lwt.return (Printf.sprintf "%d is now %s" cat_id (Cat.Name.to_repr name))
[@@patch ":id"]

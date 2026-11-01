[@@@controller "cats"]

let available (module Cats : Cats_service.S) () : Cat.t list Lwt.t =
  Cats.available ()
[@@get] [@@live [ "cats" ]] [@@summary "Cats waiting for a home"]

let find_one (module Cats : Cats_service.S) ~(cat : (Cat.t[@load Cats.find])) :
    Cat.t Lwt.t =
  Lwt.return cat
[@@get ":cat"] [@@live [ "cats" ]]

let catalog (module Cats : Cats_service.S)
    ~(page : (Forge_shared.Page.Request.t[@search])) () :
    Cat.t Forge_shared.Page.t Lwt.t =
  Cats.catalog page
[@@get "catalog"] [@@live [ "cats" ]] [@@summary "Every cat, a page at a time"]

let create (module Cats : Cats_service.S)
    ~admin:(_ : (Auth.Admin.t[@guard Auth.admin])) ~(body : Create_cat_dto.t) :
    Cat.t Lwt.t =
  Cats.create body
[@@post] [@@status 201] [@@summary "Admit a cat"]

let rename (module Cats : Cats_service.S)
    ~user:(_ : (User.t[@guard Auth.current])) ~(cat : (Cat.t[@load Cats.find]))
    ~(body : Rename_dto.t) : (Cat.t, Forge.Error.t) result Lwt.t =
  Cats.rename cat.id body
[@@put ":cat"] [@@authorize fun ~user ~cat -> Auth.owner_or_admin ~user cat]

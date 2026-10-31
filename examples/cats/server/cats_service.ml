module type S = sig
  val add : Create_cat_dto.t -> Cat.t Lwt.t
  val find_all : unit -> Cat.t list Lwt.t
  val find : int -> Cat.t option Lwt.t
end

let cats : Cat.t Dynarray.t = Dynarray.create ()

let add ({ name; age; breed } : Create_cat_dto.t) =
  let cat = { Cat.id = Dynarray.length cats + 1; name; age; breed } in
  Dynarray.add_last cats cat;
  Lwt.return cat

let find_all () = Lwt.return (Dynarray.to_list cats)

let find id =
  Lwt.return (Dynarray.find_opt (fun (cat : Cat.t) -> cat.id = id) cats)

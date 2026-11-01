module type S = sig
  val add : Create_cat_dto.t -> Cat.t Lwt.t
  val find_all : unit -> Cat.t list Lwt.t
  val find : Cat.Id.t -> Cat.t option Lwt.t
end

module Make () = struct
  let cats : Cat.t Dynarray.t = Dynarray.create ()
  let last_id = ref None

  let add ({ name; age; breed } : Create_cat_dto.t) =
    let id = Option.fold ~none:Cat.Id.first ~some:Cat.Id.succ !last_id in
    last_id := Some id;
    let cat = { Cat.id; name; age; breed } in
    Dynarray.add_last cats cat;
    Kre.Live.publish [ "cats" ];
    Lwt.return cat

  let find_all () = Lwt.return (Dynarray.to_list cats)

  let find id =
    Lwt.return
      (Dynarray.find_opt (fun (cat : Cat.t) -> Cat.Id.equal cat.id id) cats)
end

include Make ()

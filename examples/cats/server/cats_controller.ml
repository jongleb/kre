[@@@controller "cats"]
[@@@use [ Logger_middleware.use ]]

let find_all (module Cats : Cats_service.S) ~(search : (Cat_search.t[@search]))
    () : Cat.t list Lwt.t =
  let%lwt all = Cats.find_all () in
  Lwt.return
    (List.filteri
       (fun i _ -> i < search.limit)
       (List.filter
          (fun (cat : Cat.t) ->
            Option.fold ~none:true
              ~some:(fun breed ->
                String.equal (Cat.Breed.to_repr breed)
                  (Cat.Breed.to_repr cat.breed))
              search.breed)
          all))
[@@get] [@@summary "List cats"] [@@live [ "cats" ]]

let find_one (module Cats : Cats_service.S) ~(id : Cat.Id.t) :
    (Cat.t, Kre.Error.t) result Lwt.t =
  let%lwt cat = Cats.find id in
  Lwt.return (Option.to_result cat ~none:(Kre.Error.not_found "cat"))
[@@get ":id"]
[@@etag]
[@@summary "Find a cat"]
[@@description "Answers 404 when no cat has this id."]

let create (module Cats : Cats_service.S) ~(user : (string[@guard Auth.user]))
    ~(body : Create_cat_dto.t) : Cat.t Lwt.t =
  Dream.log "%s adds a cat" user;
  Cats.add body
[@@post] [@@status 201]

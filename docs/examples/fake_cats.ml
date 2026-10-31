let tom =
  {
    Cat.id = Cat.Id.first;
    name = Result.get_ok (Cat.Name.of_repr "tom");
    age = Result.get_ok (Cat.Age.of_repr 3);
    breed = Result.get_ok (Cat.Breed.of_repr "siamese");
  }

let add (_ : Create_cat_dto.t) = Lwt.return tom
let find_all () = Lwt.return [ tom ]
let find id = Lwt.return (if Cat.Id.equal id tom.id then Some tom else None)

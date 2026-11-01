let seed (module Cats : Cats_service.S) ?(count : int = 3) () : unit Lwt.t =
  Lwt_list.iter_s
    (fun number ->
      Lwt.map ignore
        (Cats.create
           {
             Create_cat_dto.name =
               Forge_shared.Validation.ok_exn
                 (Cat.Name.of_repr (Printf.sprintf "kitten %d" number));
             age = Forge_shared.Validation.ok_exn (Cat.Age.of_repr 0);
           }))
    (List.init count succ)
[@@command "Admit kittens to the shelter"]

let signup (module Users : Users_service.S)
    ~(email : Forge_shared.Refined.Email.t) ~(password : string) () : unit Lwt.t
    =
  Lwt.map
    (Result.fold
       ~ok:(fun (user : User.t) ->
         print_endline
           (Printf.sprintf "%s signed up as %s"
              (Forge_shared.Refined.Email.to_string user.email)
              (User.Role.to_string user.role)))
       ~error:(fun (error : Forge.Error.t) -> prerr_endline error.detail))
    (Users.signup { Login_dto.email; password })
[@@command "Create an account"]

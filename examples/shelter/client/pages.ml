let layout ~children = main ~children:[ children ] () [@JSX]

let failed error =
  p ~className:"error"
    ~children:[ React.string (Forge_client.Error.message error) ]
    () [@JSX]

module Adopt = struct
  let[@react.component] make ~(cat : Cat.t) =
    let message, set_message = React.useState (fun () -> "") in
    (div
       ~children:
         [
           (button
              ~onClick:(fun _ ->
                ignore
                  (Js.Promise.then_
                     (fun result ->
                       set_message (fun _ ->
                           Result.fold
                             ~ok:(fun _ -> "adopted")
                             ~error:Forge_client.Error.message result);
                       Js.Promise.resolve ())
                     (Adoptions_client.adopt
                        ~body:{ Adopt_dto.cat_id = cat.id })))
              ~children:[ React.string "Adopt" ]
              () [@JSX]);
           React.string message;
         ]
       () [@JSX])
end

module Login = struct
  let[@react.component] make ~on_login =
    let email, set_email = React.useState (fun () -> "") in
    let password, set_password = React.useState (fun () -> "") in
    let message, set_message = React.useState (fun () -> "") in
    (form
       ~onSubmit:(fun event ->
         React.Event.Form.preventDefault event;
         Result.fold
           ~error:(fun errors ->
             set_message (fun _ ->
                 String.concat ", "
                   (List.map
                      (fun (error : Forge_shared.Validation.error) ->
                        error.message)
                      (Forge_shared.Validation.to_list errors))))
           ~ok:(fun email ->
             ignore
               (Js.Promise.then_
                  (fun result ->
                    Result.fold ~ok:on_login
                      ~error:(fun error ->
                        set_message (fun _ -> Forge_client.Error.message error))
                      result;
                    Js.Promise.resolve ())
                  (Auth_client.login ~body:{ Login_dto.email; password })))
           (Forge_shared.Refined.Email.of_repr email))
       ~children:
         [
           (input ~type_:"email" ~value:email
              ~onChange:(fun event ->
                let value = (React.Event.Form.target event)##value in
                set_email (fun _ -> value))
              () [@JSX]);
           (input ~type_:"password" ~value:password
              ~onChange:(fun event ->
                let value = (React.Event.Form.target event)##value in
                set_password (fun _ -> value))
              () [@JSX]);
           (button ~type_:"submit"
              ~children:[ React.string "Log in" ]
              () [@JSX]);
           React.string message;
         ]
       () [@JSX])
end

let cats ~link ~data ~params:() ~search:() =
  Result.fold ~error:failed
    ~ok:(fun cats ->
      (ul
         ~children:
           [
             React.array
               (Array.of_list
                  (List.map
                     (fun (cat : Cat.t) ->
                       (li ~key:(Cat.Id.to_string cat.id)
                          ~children:
                            [
                              link cat
                                (React.string (Cat.Name.to_repr cat.name));
                            ]
                          () [@JSX]))
                     cats));
           ]
         () [@JSX]))
    data

let cat ~data ~params:_ ~search:() =
  Result.fold ~error:failed
    ~ok:(fun (cat : Cat.t) ->
      (article
         ~children:
           [
             (h1
                ~children:[ React.string (Cat.Name.to_repr cat.name) ]
                () [@JSX]);
             (p
                ~children:
                  [
                    React.string
                      (Printf.sprintf "%d years" (Cat.Age.to_repr cat.age));
                  ]
                () [@JSX]);
             (match cat.status with
             | Available ->
                 React.createElement Adopt.make (Adopt.makeProps ~cat ())
             | Adopted -> React.string "already adopted");
           ]
         () [@JSX]))
    data

let adoptions ~data ~params:() ~search:() =
  Result.fold ~error:failed
    ~ok:(fun adoptions ->
      (p
         ~children:
           [
             React.string
               (Printf.sprintf "%d cats adopted" (List.length adoptions));
           ]
         () [@JSX]))
    data

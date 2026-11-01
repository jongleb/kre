external argv : string array = "argv" [@@mel.scope "process"]

let account email =
  {
    Login_dto.email = Result.get_ok (Forge_shared.Refined.Email.of_repr email);
    password = "whiskers1";
  }

let kitten name =
  {
    Create_cat_dto.name = Result.get_ok (Cat.Name.of_repr name);
    age = Result.get_ok (Cat.Age.of_repr 1);
  }

let show = function
  | Ok text -> "ok " ^ text
  | Error (Forge_client.Error.Problem problem) ->
      Printf.sprintf "problem %d %s" problem.status problem.type_
  | Error error -> "error " ^ Forge_client.Error.message error

let sign_in = function
  | Ok (session : Session.t) ->
      Forge_client.Http.headers :=
        [ ("Authorization", "Bearer " ^ session.token) ];
      Ok (User.Role.to_string session.user.role)
  | Error error -> Error error

let () =
  Forge_client.Http.base_url := "http://127.0.0.1:" ^ argv.(2);
  let stop = ref ignore in
  let changed =
    Js.Promise.make (fun ~resolve ~reject:_ ->
        stop :=
          Forge_client.Live.watch Cats_client.Live.available (fun table ->
              (resolve table [@u])))
  in
  ignore
    (let open Forge_client.Promise in
     let* () =
       Js.Promise.make (fun ~resolve ~reject:_ ->
           ignore
             (Js.Global.setTimeout
                ~f:(fun () ->
                  let unit = () in
                  (resolve unit [@u]))
                300))
     in
     let* boss = Auth_client.signup ~body:(account "boss@shelter.test") in
     Js.log ("boss " ^ show (sign_in boss));
     let* tom = Cats_client.create ~body:(kitten "tom") in
     let* _ = Cats_client.create ~body:(kitten "felix") in
     let* ann = Auth_client.signup ~body:(account "ann@shelter.test") in
     Js.log ("ann " ^ show (sign_in ann));
     let* denied = Cats_client.create ~body:(kitten "kitty") in
     Js.log ("ann admits " ^ show (Result.map (fun _ -> "") denied));
     let tom = Result.get_ok tom in
     let* adopted =
       Adoptions_client.adopt ~body:{ Adopt_dto.cat_id = tom.id }
     in
     Js.log
       ("ann adopts "
       ^ show (Result.map (fun _ -> Cat.Name.to_repr tom.name) adopted));
     let* again = Adoptions_client.adopt ~body:{ Adopt_dto.cat_id = tom.id } in
     Js.log ("again " ^ show (Result.map (fun _ -> "") again));
     let* available = Cats_client.available () in
     Js.log
       ("available "
       ^ show
           (Result.map
              (fun cats ->
                String.concat ","
                  (List.map
                     (fun (cat : Cat.t) -> Cat.Name.to_repr cat.name)
                     cats))
              available));
     let+ table = changed in
     Js.log ("live " ^ table);
     Js.log
       ("login "
       ^ ReactDOMServer.renderToStaticMarkup
           (React.createElement Pages.Login.make
              (Pages.Login.makeProps ~on_login:ignore ())));
     !stop ())

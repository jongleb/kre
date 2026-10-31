external argv : string array = "argv" [@@mel.scope "process"]

let tom =
  {
    Create_cat_dto.name = Result.get_ok (Cat.Name.of_repr "tom");
    age = Result.get_ok (Cat.Age.of_repr 3);
    breed = Result.get_ok (Cat.Breed.of_repr "siamese");
    note = "";
  }

let show = function
  | Ok text -> "ok " ^ text
  | Error (Forge_client.Error.Problem problem) ->
      Printf.sprintf "problem %d %s %s" problem.status problem.type_
        (String.concat ","
           (List.map
              (fun (error : Forge_shared.Validation.error) ->
                String.concat "." error.path ^ ":" ^ error.rule)
              problem.errors))
  | Error error -> "error " ^ Forge_client.Error.message error

let () =
  Forge_client.Http.base_url := "http://127.0.0.1:" ^ argv.(2);
  Forge_client.Http.headers := [ ("X-User", "ann") ];
  let stop = ref ignore in
  let changed =
    Js.Promise.make (fun ~resolve ~reject:_ ->
        stop :=
          Forge_client.Live.watch Cats_client.Live.find_all (fun table ->
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
     let* created = Cats_client.create ~body:tom in
     Js.log
       (show
          (Result.map (fun (cat : Cat.t) -> Cat.Name.to_repr cat.name) created));
     let* rejected =
       Cats_client.create ~body:{ tom with note = "far too long for a note" }
     in
     Js.log (show (Result.map (fun _ -> "") rejected));
     let* all = Cats_client.find_all ~limit:5 () in
     Js.log
       (show (Result.map (fun cats -> string_of_int (List.length cats)) all));
     let* missing =
       Cats_client.find_one ~id:(Result.get_ok (Cat.Id.of_repr 404))
     in
     Js.log (show (Result.map (fun _ -> "") missing));
     let+ table = changed in
     Js.log ("live " ^ table);
     !stop ())

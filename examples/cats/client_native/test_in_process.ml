let tom =
  {
    Create_cat_dto.name = Result.get_ok (Cat.Name.of_repr "tom");
    age = Result.get_ok (Cat.Age.of_repr 3);
    breed = Result.get_ok (Cat.Breed.of_repr "siamese");
    note = "";
  }

module Cats_api =
  [%http_client:
  val find_one : id:Cat.Id.t -> Cat.t [@@get "/cats/:id"]
  val find_all : ?limit:int -> unit -> Cat.t list [@@get "/cats"]
  val create : body:Create_cat_dto.t -> Cat.t [@@post "/cats"]]

module Cats_http = Cats_api (struct
  let url = "http://cats.internal"
  let headers = [ ("X-User", "bob") ]
end)

let outcome = function
  | Ok (cat : Cat.t) -> "ok " ^ Cat.Name.to_repr cat.name
  | Error (Kre_client.Error.Problem problem) ->
      Printf.sprintf "%d %s" problem.status
        (String.concat ","
           (List.map
              (fun (error : Kre_shared.Validation.error) ->
                String.concat "." error.path ^ ":" ^ error.rule)
              problem.errors))
  | Error error -> Kre_client.Error.message error

let () =
  let module Fresh = Cats_service.Make () in
  Kre_testing.use [ Cats_controller.register (module Fresh) ];
  Kre_client.Http.headers := [ ("X-User", "ann") ];
  Lwt_main.run
    (Alcotest_lwt.run "in-process client"
       [
         ( "cats",
           [
             Alcotest_lwt.test_case "typed calls, no socket" `Quick (fun _ () ->
                 let%lwt created = Cats_client.create ~body:tom in
                 let%lwt rejected =
                   Cats_client.create
                     ~body:{ tom with note = "far too long for a note" }
                 in
                 let%lwt missing =
                   Cats_client.find_one ~id:(Result.get_ok (Cat.Id.of_repr 9))
                 in
                 Alcotest.(check (list string))
                   "outcomes"
                   [ "ok tom"; "422 note:max_length"; "404 " ]
                   [ outcome created; outcome rejected; outcome missing ];
                 Lwt.return_unit);
             Alcotest_lwt.test_case "a declared HTTP client" `Quick (fun _ () ->
                 let%lwt created =
                   Cats_http.create ~body:{ tom with note = "" }
                 in
                 let%lwt all = Cats_http.find_all ~limit:1 () in
                 let%lwt missing =
                   Cats_http.find_one ~id:(Result.get_ok (Cat.Id.of_repr 99))
                 in
                 Alcotest.(check (list string))
                   "outcomes"
                   [ "ok tom"; "1 cat"; "404 " ]
                   [
                     outcome created;
                     Result.fold
                       ~ok:(fun cats ->
                         Printf.sprintf "%d cat" (List.length cats))
                       ~error:Kre_client.Error.message all;
                     outcome missing;
                   ];
                 Lwt.return_unit);
           ] );
       ])

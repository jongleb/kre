let port = 18000 + (Unix.getpid () mod 1000)

let ok = function
  | Ok value -> value
  | Error error -> Alcotest.fail (Forge_client.Error.message error)

let problem = function
  | Ok _ -> Alcotest.fail "expected a problem"
  | Error (Forge_client.Error.Problem problem) -> problem
  | Error error -> Alcotest.fail (Forge_client.Error.message error)

let tom =
  {
    Create_cat_dto.name = Result.get_ok (Cat.Name.of_repr "tom");
    age = Result.get_ok (Cat.Age.of_repr 3);
    breed = Result.get_ok (Cat.Breed.of_repr "siamese");
    note = "";
  }

let tests =
  [
    Alcotest_lwt.test_case "create, then read back" `Quick (fun _ () ->
        let%lwt created = Cats_client.create ~body:tom in
        let cat = ok created in
        let%lwt found = Cats_client.find_one ~id:cat.id in
        Alcotest.(check string) "name" "tom" (Cat.Name.to_repr (ok found).name);
        Lwt.return_unit);
    Alcotest_lwt.test_case "optional query parameter" `Quick (fun _ () ->
        let%lwt none =
          Cats_client.find_all ~search:{ Cat_search.limit = 0; breed = None }
        in
        let%lwt all =
          Cats_client.find_all ~search:{ Cat_search.limit = 20; breed = None }
        in
        Alcotest.(check (pair int int))
          "lengths" (0, 1)
          (List.length (ok none), List.length (ok all));
        Lwt.return_unit);
    Alcotest_lwt.test_case "404 arrives as Problem Details" `Quick (fun _ () ->
        let%lwt missing =
          Cats_client.find_one ~id:(Result.get_ok (Cat.Id.of_repr 404))
        in
        Alcotest.(check (pair int string))
          "problem"
          (404, "urn:forge:error:not_found")
          (let problem = problem missing in
           (problem.status, problem.type_));
        Lwt.return_unit);
    Alcotest_lwt.test_case "unreachable server is a network error" `Quick
      (fun _ () ->
        let base = !Forge_client.Http.base_url in
        Forge_client.Http.base_url := "http://127.0.0.1:1";
        let%lwt result =
          Cats_client.find_all ~search:{ Cat_search.limit = 20; breed = None }
        in
        Forge_client.Http.base_url := base;
        Alcotest.(check bool)
          "network" true
          (match result with
          | Error (Forge_client.Error.Network _) -> true
          | _ -> false);
        Lwt.return_unit);
  ]

let () =
  Forge_client.Http.base_url := Printf.sprintf "http://127.0.0.1:%d" port;
  Forge_client.Http.headers := [ ("X-User", "ann") ];
  let stop, stopper = Lwt.wait () in
  Lwt_main.run
    (let server =
       Dream.serve ~interface:"127.0.0.1" ~port ~stop
         (Forge.App.handler [ Cats_controller.register (module Cats_service) ])
     in
     let%lwt () = Lwt_unix.sleep 0.2 in
     let%lwt () =
       Alcotest_lwt.run ~and_exit:false "generated client" [ ("cats", tests) ]
     in
     Lwt.wakeup_later stopper ();
     server)

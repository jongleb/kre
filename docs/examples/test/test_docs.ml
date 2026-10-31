let call ?(headers = []) ?(body = "") handler method_ target =
  let response =
    Dream.test handler (Dream.request ~method_ ~target ~headers body)
  in
  ( Dream.status_to_int (Dream.status response),
    Lwt_main.run (Dream.body response) )

let app controllers = Forge.App.handler controllers

let () =
  Alcotest.run "docs"
    [
      ( "examples",
        [
          Alcotest.test_case "guards: controller-wide, then evidence" `Quick
            (fun () ->
              let admin =
                app [ Admin_controller.register (module Fake_cats) ]
              in
              Alcotest.(check (list int))
                "statuses" [ 401; 403; 204 ]
                (List.map
                   (fun headers ->
                     fst (call ~headers admin `DELETE "/admin/cats"))
                   [
                     [];
                     [ ("X-User", "ann") ];
                     [ ("X-User", "ann"); ("X-Role", "admin") ];
                   ]));
          Alcotest.test_case "custom decorators" `Quick (fun () ->
              Alcotest.(check (pair int string))
                "whoami" (200, "127.0.0.1:0 fr")
                (call
                   ~headers:[ ("Accept-Language", "fr") ]
                   (app [ Whoami_controller.register () ])
                   `GET "/whoami"));
          Alcotest.test_case "request scope" `Quick (fun () ->
              let trace = app [ Trace_controller.register () ] in
              let first = call trace `GET "/trace" in
              let second = call trace `GET "/trace" in
              Alcotest.(check (list string))
                "ids"
                [ "request 1"; "request 2" ]
                [ snd first; snd second ]);
          Alcotest.test_case "exception filter" `Quick (fun () ->
              Alcotest.(check (pair int string))
                "page"
                (404, "<h1>Nothing here</h1>")
                (call
                   (Forge.App.handler ~error_handler:Error_pages.handler [])
                   `GET "/missing"));
          Alcotest.test_case "redirect, timeout, header, controller filter"
            `Quick (fun () ->
              let legacy = app [ Legacy_controller.register () ] in
              let header target name =
                Dream.header (Dream.test legacy (Dream.request ~target "")) name
              in
              Alcotest.(check (list (pair int string)))
                "responses"
                [
                  (302, "");
                  (504, "");
                  (200, "fresh");
                  (404, "<h1>Nothing here</h1>");
                ]
                (List.map
                   (fun target ->
                     match call legacy `GET target with
                     | 504, _ -> (504, "")
                     | response -> response)
                   [
                     "/legacy/cats";
                     "/legacy/slow";
                     "/legacy/fresh";
                     "/legacy/gone";
                   ]);
              Alcotest.(check (pair (option string) (option string)))
                "headers"
                (Some "/cats", Some "no-store")
                ( header "/legacy/cats" "Location",
                  header "/legacy/fresh" "Cache-Control" ));
          Alcotest.test_case "[@@authorize] sees typed arguments" `Quick
            (fun () ->
              let notes = app [ Notes_controller.register () ] in
              Alcotest.(check (list (pair int string)))
                "responses"
                [ (200, "note 1 for ann"); (403, ""); (401, "") ]
                (List.map
                   (fun (headers, target) ->
                     match call ~headers notes `GET target with
                     | ((403 | 401) as status), _ -> (status, "")
                     | response -> response)
                   [
                     ([ ("X-User", "ann") ], "/notes/1");
                     ([ ("X-User", "ann") ], "/notes/2");
                     ([], "/notes/1");
                   ]));
          Alcotest.test_case "jwt login, then a role" `Quick (fun () ->
              let session = app [ Session_controller.register () ] in
              let token =
                snd
                  ( Dream.test session
                      (Dream.request ~method_:`POST ~target:"/session/login"
                         {|{"user":"root","password":"secret"}|})
                  |> fun response ->
                    (response, Lwt_main.run (Dream.body response)) )
              in
              let reset headers =
                fst (call ~headers session `POST "/session/reset")
              in
              Alcotest.(check (list int))
                "statuses" [ 204; 401 ]
                [ reset [ ("Authorization", "Bearer " ^ token) ]; reset [] ]);
          Alcotest.test_case "server-sent events" `Quick (fun () ->
              let response =
                Dream.test
                  (app [ Ticks_controller.register () ])
                  (Dream.request ~target:"/ticks?upto=3" "")
              in
              Alcotest.(check (pair (option string) string))
                "stream"
                ( Some "text/event-stream",
                  "data: {\"n\":0}\n\ndata: {\"n\":1}\n\ndata: {\"n\":2}\n\n" )
                ( Dream.header response "Content-Type",
                  Lwt_main.run (Dream.body response) ));
          Alcotest.test_case "parameter decorators" `Quick (fun () ->
              let entities = app [ Entities_controller.register () ] in
              let update headers =
                call ~headers ~body:{|{"displayName":"Ann"}|} entities `PUT
                  "/entities/7?page-size=20"
              in
              Alcotest.(check (list (pair int string)))
                "responses"
                [
                  (200, "7 Ann web - dark 20 127.0.0.1");
                  (400, "missing");
                  (200, "3 is now tom");
                  (422, "invalid");
                ]
                [
                  update [ ("X-Client-Name", "web"); ("Cookie", "theme=dark") ];
                  (match update [] with
                  | 400, _ -> (400, "missing")
                  | other -> other);
                  call ~body:{|{"name":"tom"}|} entities `PATCH "/entities/3";
                  (match
                     call ~body:{|{"name":""}|} entities `PATCH "/entities/3"
                   with
                  | 422, _ -> (422, "invalid")
                  | other -> other);
                ]);
          Alcotest.test_case "interceptors" `Quick (fun () ->
              let audit = app [ Audit_controller.register () ] in
              let statuses =
                List.map
                  (fun target -> fst (call audit `GET target))
                  [ "/audit/1"; "/audit/2"; "/audit/slow" ]
              in
              Alcotest.(check (pair (list int) int))
                "statuses and calls"
                ([ 200; 403; 504 ], 2)
                (statuses, !Audit_controller.calls));
          Alcotest.test_case "verbs, wildcard, HEAD fallback" `Quick (fun () ->
              let files = app [ Files_controller.register () ] in
              Alcotest.(check (list (pair int string)))
                "responses"
                [
                  (200, "file docs/guide.pdf");
                  (200, "");
                  (204, "");
                  (200, "PATCH");
                  (200, "GET");
                  (200, "HEAD");
                ]
                [
                  call files `GET "/files/docs/guide.pdf";
                  call files `HEAD "/files/docs/guide.pdf";
                  call files `OPTIONS "/files/probe";
                  call files `PATCH "/files/echo";
                  call files `GET "/files/echo";
                  (match call files `HEAD "/files/echo" with
                  | 200, _ -> (200, "HEAD")
                  | other -> other);
                ]);
          Alcotest.test_case "host routing" `Quick (fun () ->
              let tenant = app [ Tenant_controller.register () ] in
              Alcotest.(check (list (pair int string)))
                "responses"
                [ (200, "acme"); (404, "") ]
                [
                  call
                    ~headers:[ ("Host", "acme.example.com") ]
                    tenant `GET "/tenant";
                  (match
                     call
                       ~headers:[ ("Host", "acme.other.org") ]
                       tenant `GET "/tenant"
                   with
                  | 404, _ -> (404, "")
                  | other -> other);
                ]);
          Alcotest.test_case "serialization: exclude, transform, mapped types"
            `Quick (fun () ->
              let ann =
                Account.of_json
                  (Yojson.Basic.from_string
                     {|{"id":1,"email":"ann@x.io","password":"s3cret","displayName":"  Ann "}|})
              in
              let patched =
                Account.update_apply
                  (Account.update_of_json
                     (Yojson.Basic.from_string {|{"email":"new@x.io"}|}))
                  ann
              in
              Alcotest.(check (list string))
                "json"
                [
                  {|{"id":1,"email":"ann@x.io","displayName":"Ann"}|};
                  {|{"id":1,"displayName":"Ann"}|};
                  "new@x.io / s3cret";
                  "true";
                ]
                [
                  Yojson.Basic.to_string (Account.to_json ann);
                  Yojson.Basic.to_string
                    (Account.summary_to_json (Account.summary_of_t ann));
                  patched.email ^ " / " ^ patched.password;
                  Yojson.Basic.to_string
                    Yojson.Basic.Util.(
                      member "writeOnly"
                        (member "password"
                           (member "properties" Account.t_jsonschema)));
                ]);
          Alcotest.test_case "response cache" `Quick (fun () ->
              let stats = app [ Stats_controller.register () ] in
              let fetch () =
                let response =
                  Dream.test stats (Dream.request ~target:"/stats" "")
                in
                ( Lwt_main.run (Dream.body response),
                  Option.value (Dream.header response "X-Cache") ~default:"-" )
              in
              let first = fetch () in
              let second = fetch () in
              Alcotest.(check (list (pair string string)))
                "responses"
                [ ("computed 1 times", "miss"); ("computed 1 times", "hit") ]
                [ first; second ]);
          Alcotest.test_case "websocket gateway" `Quick (fun () ->
              let chat = Chat_gateway.gateway () in
              let inbox = ref [] in
              let client name =
                fst
                  (Forge.Gateway.connect chat ~send:(fun frame ->
                       inbox := (name ^ " " ^ frame) :: !inbox;
                       Lwt.return_unit))
              in
              let ann = client "ann" in
              let _bob = client "bob" in
              Lwt_main.run
                (let open Lwt.Syntax in
                 let* () = ann {|{"event":"ping"}|} in
                 let* () =
                   ann {|{"event":"say","data":{"author":"ann","text":"hi"}}|}
                 in
                 let* () = ann {|{"event":"say","data":{"author":"ann"}}|} in
                 ann {|{"event":"dance"}|});
              Alcotest.(check (list string))
                "frames"
                [
                  {|ann {"event":"ping","data":"pong"}|};
                  {|bob {"event":"said","data":{"author":"ann","text":"hi"}}|};
                  {|ann {"event":"said","data":{"author":"ann","text":"hi"}}|};
                  {|ann {"event":"say","data":{"author":"ann","text":"ack: hi"}}|};
                  "ann error 422";
                  "ann error 404";
                ]
                (List.map
                   (fun line ->
                     match String.index_opt line ' ' with
                     | None -> line
                     | Some space -> (
                         let name = String.sub line 0 space in
                         let frame =
                           Yojson.Basic.from_string
                             (String.sub line (space + 1)
                                (String.length line - space - 1))
                         in
                         match Yojson.Basic.Util.member "event" frame with
                         | `String "error" ->
                             Printf.sprintf "%s error %d" name
                               Yojson.Basic.Util.(
                                 to_int (member "status" (member "data" frame)))
                         | _ -> line))
                   (List.rev !inbox)));
          Alcotest.test_case "handler-level version and error handler" `Quick
            (fun () ->
              let legacy = app [ Legacy_controller.register () ] in
              let plain =
                Dream.test legacy (Dream.request ~target:"/legacy/plain" "")
              in
              Alcotest.(check (pair (pair int string) (option string)))
                "responses"
                ((200, "v2"), Some "application/problem+json")
                ( call legacy `GET "/v2/legacy/status",
                  Dream.header plain "Content-Type" ));
          Alcotest.test_case "file upload" `Quick (fun () ->
              let uploads = app [ Uploads_controller.register () ] in
              let part name ?filename content =
                Printf.sprintf
                  "--X\r\n\
                   Content-Disposition: form-data; name=\"%s\"%s\r\n\
                   \r\n\
                   %s\r\n"
                  name
                  (Option.fold ~none:""
                     ~some:(Printf.sprintf "; filename=\"%s\"")
                     filename)
                  content
              in
              let body =
                String.concat ""
                  [
                    part "title" "me";
                    part "tag" "cat";
                    part "tag" "orange";
                    part "avatar" ~filename:"me.png" "PNGDATA";
                    "--X--\r\n";
                  ]
              in
              Alcotest.(check (list (pair int string)))
                "responses"
                [ (200, "me: me.png, 7 bytes, tags cat,orange"); (415, "") ]
                [
                  call
                    ~headers:
                      [ ("Content-Type", "multipart/form-data; boundary=X") ]
                    ~body uploads `POST "/uploads/avatar";
                  (match call ~body:"{}" uploads `POST "/uploads/avatar" with
                  | 415, _ -> (415, "")
                  | other -> other);
                ]);
          Alcotest.test_case "fake provider" `Quick (fun () ->
              Alcotest.(check int)
                "found" 200
                (fst
                   (call
                      (app (Composition.controllers ~fake:`Fake))
                      `GET "/cats/1")));
        ] );
    ]

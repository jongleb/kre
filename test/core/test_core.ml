open Forge_shared

module Name = Refined.String (struct
  let name = "name"
  let min = 1
  let max = 4
end)

module Age = Refined.Int (struct
  let name = "age"
  let min = 0
  let max = 40
end)

module Breed = Refined.Enum (struct
  let name = "breed"
  let values = [ "siamese"; "persian" ]
end)

module Cat = struct
  type t = { id : int; name : string }

  let of_json json =
    match Jsonkit.classify json with
    | `Assoc fields ->
        {
          id = Scalar.Int.of_json (List.assoc "id" fields);
          name = Scalar.String.of_json (List.assoc "name" fields);
        }
    | _ -> raise (Validation.Invalid (Validation.fail ~rule:"type" "object"))

  let to_json { id; name } = `Assoc [ ("id", `Int id); ("name", `String name) ]

  let t_jsonschema =
    `Assoc
      [
        ("type", `String "object");
        ( "properties",
          `Assoc
            [
              ("id", Scalar.Int.t_jsonschema);
              ("name", Scalar.String.t_jsonschema);
            ] );
      ]
end

let json = Alcotest.testable Yojson.Basic.pp Yojson.Basic.equal

let rules errors =
  List.map (fun (e : Validation.error) -> e.rule) (Validation.to_list errors)

let rules_of = function Ok _ -> [] | Error errors -> rules errors

let validation =
  [
    Alcotest.test_case "check keeps passing value" `Quick (fun () ->
        Alcotest.(check (result string reject))
          "ok" (Ok "ab")
          (Result.map_error ignore
             (Validation.check [ Validation.min_length 1 ] "ab")));
    Alcotest.test_case "check collects every failure" `Quick (fun () ->
        Alcotest.(check (list string))
          "rules" [ "min_length"; "one_of" ]
          (rules_of
             (Validation.check
                [
                  Validation.min_length 5;
                  Validation.max_length 10;
                  Validation.one_of [ "x" ];
                ]
                "abc")));
    Alcotest.test_case "and+ keeps the failures of both sides" `Quick (fun () ->
        Alcotest.(check (list (pair (list string) string)))
          "errors"
          [ ([ "a" ], "min_length"); ([ "b" ], "range") ]
          (Result.fold
             ~ok:(fun _ -> [])
             ~error:(fun errors ->
               List.map
                 (fun (e : Validation.error) -> (e.path, e.rule))
                 (Validation.to_list errors))
             (let open Validation.Syntax in
              let+ a = Validation.field "a" [ Validation.min_length 2 ] "x"
              and+ b =
                Validation.field "b" [ Validation.range ~min:0 ~max:1 ] 5
              in
              (a, b))));
    Alcotest.test_case "email" `Quick (fun () ->
        Alcotest.(check (list (list string)))
          "rules"
          [ []; [ "email" ]; [ "email" ]; [ "email" ] ]
          (List.map
             (fun s -> rules_of (Validation.check [ Validation.email ] s))
             [ "a@b.co"; "ab.co"; "a@b"; "a b@c.de" ]));
    Alcotest.test_case "to_json" `Quick (fun () ->
        Alcotest.check json "errors"
          (`List
             [
               `Assoc
                 [
                   ("path", `List []);
                   ("rule", `String "range");
                   ("message", `String "bad");
                 ];
             ])
          (Validation.to_json (Validation.fail ~rule:"range" "bad")));
  ]

let scalar =
  [
    Alcotest.test_case "of_string" `Quick (fun () ->
        Alcotest.(check (list (list string)))
          "rules"
          [ []; [ "type" ]; []; [ "type" ] ]
          [
            rules_of (Scalar.Int.of_string "42");
            rules_of (Scalar.Int.of_string "x");
            rules_of (Scalar.Bool.of_string "true");
            rules_of (Scalar.Bool.of_string "1");
          ]);
    Alcotest.test_case "float prints shortest round-trip" `Quick (fun () ->
        Alcotest.(check (list string))
          "printed" [ "0.1"; "3"; "1e+100" ]
          (List.map Scalar.Float.to_string [ 0.1; 3.; 1e100 ]));
    Alcotest.test_case "int64 travels as a JSON string" `Quick (fun () ->
        Alcotest.check json "json" (`String "9007199254740993")
          (Scalar.Int64.to_json 9007199254740993L));
  ]

let json_tests =
  [
    Alcotest.test_case "parse ok" `Quick (fun () ->
        Alcotest.(check (list int))
          "ids" [ 1; 2 ]
          (List.map
             (fun (c : Cat.t) -> c.id)
             (Result.get_ok
                (Json.parse
                   (module Json.List (Cat))
                   (`List
                      [
                        `Assoc [ ("id", `Int 1); ("name", `String "a") ];
                        `Assoc [ ("id", `Int 2); ("name", `String "b") ];
                      ])))));
    Alcotest.test_case "parse turns a type mismatch into an error" `Quick
      (fun () ->
        Alcotest.(check (list string))
          "rules" [ "type" ]
          (rules_of (Json.parse (module Scalar.Int) (`String "x"))));
  ]

let refined =
  [
    Alcotest.test_case "of_repr applies the rules" `Quick (fun () ->
        Alcotest.(check (list (list string)))
          "rules"
          [ []; [ "min_length" ]; [ "max_length" ] ]
          (List.map (fun s -> rules_of (Name.of_repr s)) [ "tom"; ""; "tommy" ]));
    Alcotest.test_case "of_json raises with the rule" `Quick (fun () ->
        Alcotest.(check (list string))
          "rules" [ "range" ]
          (rules_of (Json.parse (module Age) (`Int 41))));
    Alcotest.test_case "of_string checks too" `Quick (fun () ->
        Alcotest.(check (list (list string)))
          "rules"
          [ []; [ "one_of" ]; [ "type" ] ]
          [
            rules_of (Breed.of_string "persian");
            rules_of (Breed.of_string "sphynx");
            rules_of (Age.of_string "x");
          ]);
    Alcotest.test_case "schema carries the constraints" `Quick (fun () ->
        Alcotest.check json "schema"
          (`Assoc
             [
               ("title", `String "name");
               ("type", `String "string");
               ("minLength", `Int 1);
               ("maxLength", `Int 4);
             ])
          Name.t_jsonschema);
    Alcotest.test_case "email" `Quick (fun () ->
        Alcotest.(check (list (list string)))
          "rules" [ []; [ "email" ] ]
          [
            rules_of (Refined.Email.of_repr "me@x.io");
            rules_of (Refined.Email.of_repr "me");
          ]);
  ]

let body response = Lwt_main.run (Dream.body response)
let status response = Dream.status_to_int (Dream.status response)
let get target = Dream.request ~method_:`GET ~target ""

let error =
  [
    Alcotest.test_case "to_json is Problem Details" `Quick (fun () ->
        Alcotest.check json "problem"
          (`Assoc
             [
               ("type", `String "urn:forge:error:validation");
               ("title", `String "Unprocessable Entity");
               ("status", `Int 422);
               ("detail", `String "validation failed");
               ("instance", `String "/cats");
               ( "errors",
                 `List
                   [
                     `Assoc
                       [
                         ("path", `List []);
                         ("rule", `String "range");
                         ("message", `String "must be between 0 and 40");
                       ];
                   ] );
             ])
          (Forge.Error.to_json ~instance:"/cats"
             (Forge.Error.unprocessable
                (Validation.fail ~rule:"range" "must be between 0 and 40"))));
    Alcotest.test_case "to_response" `Quick (fun () ->
        let response =
          Dream.test
            (fun request ->
              Forge.Error.to_response request (Forge.Error.conflict "taken"))
            (get "/x")
        in
        Alcotest.(check (pair int (option string)))
          "status and type"
          (409, Some "application/problem+json")
          (status response, Dream.header response "Content-Type"));
  ]

let user : string Dream.field = Dream.new_field ()

let guard =
  [
    Alcotest.test_case "field and header" `Quick (fun () ->
        let request = Dream.request ~headers:[ ("X-Key", "k") ] "" in
        Dream.set_field request user "tom";
        let guarded =
          Lwt_main.run
            (Forge.Guard.both
               (Forge.Guard.field user
                  ~missing:(Forge.Error.unauthorized "login"))
               (Forge.Guard.header "X-Key")
               request)
        in
        Alcotest.(check (result (pair string string) reject))
          "both"
          (Ok ("tom", "k"))
          (Result.map_error ignore guarded));
    Alcotest.test_case "missing field" `Quick (fun () ->
        let guarded =
          Lwt_main.run
            (Forge.Guard.field user
               ~missing:(Forge.Error.unauthorized "login")
               (get "/"))
        in
        Alcotest.(check (option string))
          "code" (Some "unauthorized")
          (Option.map
             (fun (e : Forge.Error.t) -> e.code)
             (Result.fold ~ok:(fun _ -> None) ~error:Option.some guarded)));
  ]

let cats = [ { Cat.id = 1; name = "tom" }; { Cat.id = 2; name = "felix" } ]

let admin : unit Forge.Guard.t =
 fun request ->
  Lwt.return
    (Option.fold
       ~none:(Error (Forge.Error.forbidden "admin only"))
       ~some:(fun _ -> Ok ())
       (Dream.header request "X-Admin"))

let tag : Dream.middleware =
 fun next request ->
  Lwt.map
    (fun response ->
      Dream.add_header response "X-Controller" "cats";
      response)
    (next request)

let controller =
  Forge.Controller.v ~middleware:[ tag ]
    ~spec:{ Forge.Spec.prefix = "/cats"; version = None; routes = [] }
    [
      Forge.Route.v `GET
        Routes.(
          (s "cats" /? nil)
          @--> Forge.Route.handle ~status:`OK
                 (Forge.Route.Json (module Json.List (Cat)))
                 (fun _ -> Lwt.return_ok cats));
      Forge.Route.v `GET
        Routes.(
          (s "cats" / int /? nil) @--> fun id ->
          Forge.Route.handle ~status:`OK
            (Forge.Route.Found (module Cat))
            (fun _ ->
              Lwt.return_ok (List.find_opt (fun (c : Cat.t) -> c.id = id) cats)));
      Forge.Route.v `POST
        Routes.(
          (s "cats" /? nil)
          @--> Forge.Route.handle ~status:`Created ~guards:[ admin ]
                 Forge.Route.Text (fun _ -> Lwt.return_ok "created"));
      Forge.Route.v `DELETE
        Routes.(
          (s "cats" / int /? nil) @--> fun _ ->
          Forge.Route.handle ~status:`No_Content Forge.Route.Unit (fun _ ->
              failwith "boom"));
      Forge.Route.v `PUT
        Routes.(
          (s "cats" / int /? nil) @--> fun _ ->
          Forge.Route.handle ~status:`OK Forge.Route.Unit (fun _ ->
              Forge.Error.fail (Forge.Error.conflict "locked")));
    ]

let app = Dream.test (Forge.App.handler [ controller ])

let app_tests =
  [
    Alcotest.test_case "empty app answers 404 Problem Details" `Quick (fun () ->
        let response = Dream.test (Forge.App.handler []) (get "/anything") in
        Alcotest.(check (pair int json))
          "404"
          ( 404,
            `Assoc
              [
                ("type", `String "urn:forge:error:not_found");
                ("title", `String "Not Found");
                ("status", `Int 404);
                ("detail", `String "no route for GET /anything");
                ("instance", `String "/anything");
              ] )
          (status response, Yojson.Basic.from_string (body response)));
    Alcotest.test_case "json list" `Quick (fun () ->
        let response = app (get "/cats") in
        Alcotest.(check (triple int string (option string)))
          "list"
          (200, {|[{"id":1,"name":"tom"},{"id":2,"name":"felix"}]|}, Some "cats")
          (status response, body response, Dream.header response "X-Controller"));
    Alcotest.test_case "typed path param and found" `Quick (fun () ->
        Alcotest.(check (list int))
          "statuses" [ 200; 404; 404 ]
          (List.map
             (fun target -> status (app (get target)))
             [ "/cats/2"; "/cats/3"; "/cats/x" ]));
    Alcotest.test_case "query string is ignored by matching" `Quick (fun () ->
        Alcotest.(check int) "status" 200 (status (app (get "/cats?limit=1"))));
    Alcotest.test_case "trailing slash redirects" `Quick (fun () ->
        let response = app (get "/cats/?limit=1") in
        Alcotest.(check (pair int (option string)))
          "301"
          (301, Some "/cats?limit=1")
          (status response, Dream.header response "Location"));
    Alcotest.test_case "guard rejects, then admits" `Quick (fun () ->
        let post headers =
          app (Dream.request ~method_:`POST ~target:"/cats" ~headers "")
        in
        Alcotest.(check (list int))
          "statuses" [ 403; 201 ]
          [ status (post []); status (post [ ("X-Admin", "1") ]) ]);
    Alcotest.test_case "exceptions become 500, Error.fail keeps its status"
      `Quick (fun () ->
        Alcotest.(check (list int))
          "statuses" [ 500; 409 ]
          [
            status (app (Dream.request ~method_:`DELETE ~target:"/cats/1" ""));
            status (app (Dream.request ~method_:`PUT ~target:"/cats/1" ""));
          ]);
    Alcotest.test_case "custom error handler" `Quick (fun () ->
        let response =
          Dream.test
            (Forge.App.handler
               ~error_handler:(fun _ _ ->
                 Dream.respond ~status:`Not_Found "nope")
               [])
            (get "/x")
        in
        Alcotest.(check string) "body" "nope" (body response));
  ]

let spec =
  [
    Alcotest.test_case "to_json" `Quick (fun () ->
        Alcotest.check json "spec"
          (`Assoc
             [
               ("prefix", `String "/cats");
               ("version", `Null);
               ( "routes",
                 `List
                   [
                     `Assoc
                       [
                         ("verb", `String "GET");
                         ("path", `String "/cats/:id");
                         ("name", `String "find_one");
                         ( "params",
                           `List
                             [
                               `Assoc
                                 [
                                   ("name", `String "id");
                                   ("label", `String "id");
                                   ("in", `String "path");
                                   ("presence", `String "required");
                                   ( "value",
                                     `Assoc
                                       [
                                         ("type", `String "int");
                                         ( "module",
                                           `String "Forge_shared.Scalar.Int" );
                                         ("schema", Scalar.Int.t_jsonschema);
                                       ] );
                                 ];
                             ] );
                         ("body", `Null);
                         ( "returns",
                           `Assoc
                             [
                               ("type", `String "Cat.t");
                               ("module", `String "Cat");
                               ("schema", Cat.t_jsonschema);
                             ] );
                         ("status", `Int 200);
                         ("guards", `List []);
                         ("summary", `Null);
                         ("description", `Null);
                       ];
                   ] );
             ])
          (Forge.Spec.to_json
             {
               prefix = "/cats";
               version = None;
               routes =
                 [
                   {
                     verb = `GET;
                     path = "/cats/:id";
                     name = "find_one";
                     params =
                       [
                         {
                           name = "id";
                           label = "id";
                           location = Path;
                           value =
                             {
                               type_ = "int";
                               module_ = "Forge_shared.Scalar.Int";
                               schema = Scalar.Int.t_jsonschema;
                             };
                         };
                       ];
                     body = None;
                     returns =
                       Json
                         {
                           type_ = "Cat.t";
                           module_ = "Cat";
                           schema = Cat.t_jsonschema;
                         };
                     status = `OK;
                     guards = [];
                     summary = None;
                     description = None;
                   };
                 ];
             }));
  ]

let migration =
  [
    Alcotest.test_case "statements end at ; and skip comments" `Quick (fun () ->
        Alcotest.(check (result (pair (list string) (list string)) string))
          "sections"
          (Ok
             ( [ "CREATE TABLE a (\nid BIGINT\n)"; "INSERT INTO a VALUES (1)" ],
               [ "DROP TABLE a" ] ))
          (Result.map
             (fun (m : Forge.Migration.t) -> (m.up, m.down))
             (Forge.Migration.parse ~version:"0001_a"
                "-- header\n\
                 -- migrate:up\n\
                 CREATE TABLE a (\n\
                \  id BIGINT\n\
                 );\n\
                 -- a comment\n\
                 INSERT INTO a VALUES (1);\n\
                 -- migrate:down\n\
                 DROP TABLE a;\n")));
    Alcotest.test_case "a file needs an up section" `Quick (fun () ->
        Alcotest.(check (list (result reject string)))
          "errors"
          [
            Error "0001_a: no -- migrate:up section";
            Error "0001_a: the up section has no statements";
          ]
          (List.map
             (fun text ->
               Result.map ignore (Forge.Migration.parse ~version:"0001_a" text))
             [
               "DROP TABLE a;"; "-- migrate:up\n-- migrate:down\nDROP TABLE a;";
             ]));
  ]

let ok_handler _ = Dream.respond "ok"

let security =
  [
    Alcotest.test_case "cors: preflight and simple requests" `Quick (fun () ->
        let cors =
          Dream.test
            (Forge.Cors.middleware
               ~origins:(Forge.Cors.Only [ "https://cats.io" ]) () ok_handler)
        in
        let preflight =
          cors
            (Dream.request ~method_:`OPTIONS ~target:"/cats"
               ~headers:
                 [
                   ("Origin", "https://cats.io");
                   ("Access-Control-Request-Method", "POST");
                 ]
               "")
        in
        let simple origin =
          Dream.header
            (cors
               (Dream.request ~target:"/cats"
                  ~headers:[ ("Origin", origin) ]
                  ""))
            "Access-Control-Allow-Origin"
        in
        Alcotest.(check (list (option string)))
          "headers"
          [
            Some "https://cats.io";
            Some "GET, POST, PUT, PATCH, DELETE";
            Some "https://cats.io";
            None;
          ]
          [
            Dream.header preflight "Access-Control-Allow-Origin";
            Dream.header preflight "Access-Control-Allow-Methods";
            simple "https://cats.io";
            simple "https://evil.io";
          ]);
    Alcotest.test_case "secure headers keep what the handler set" `Quick
      (fun () ->
        let response =
          Dream.test
            (Forge.Secure_headers.middleware () (fun _ ->
                 Dream.respond
                   ~headers:[ ("X-Frame-Options", "SAMEORIGIN") ]
                   "ok"))
            (Dream.request "")
        in
        Alcotest.(check (list (option string)))
          "headers"
          [ Some "nosniff"; Some "SAMEORIGIN"; Some "default-src 'self'" ]
          [
            Dream.header response "X-Content-Type-Options";
            Dream.header response "X-Frame-Options";
            Dream.header response "Content-Security-Policy";
          ]);
    Alcotest.test_case "rate limit: a fixed window per client" `Quick (fun () ->
        let now = ref 0. in
        let limited =
          Dream.test
            (Forge.Rate_limit.middleware ~limit:2 ~window:10.
               ~clock:(fun () -> !now)
               () ok_handler)
        in
        let hit () =
          let response = limited (Dream.request "") in
          ( Dream.status_to_int (Dream.status response),
            Dream.header response "Retry-After" )
        in
        let first = hit () in
        let second = hit () in
        now := 4.;
        let third = hit () in
        now := 11.;
        let fourth = hit () in
        Alcotest.(check (list (pair int (option string))))
          "statuses"
          [ (200, None); (200, None); (429, Some "6"); (200, None) ]
          [ first; second; third; fourth ]);
  ]

let jwt =
  let token = Forge.Jwt.sign ~secret:"s" ~now:1000. ~expires_in:60. "ann" in
  let outcome = function
    | Ok (claims : Forge.Jwt.claims) -> "ok " ^ claims.subject
    | Error (`Jwt Forge.Jwt.Malformed) -> "malformed"
    | Error (`Jwt Forge.Jwt.Bad_signature) -> "bad signature"
    | Error (`Jwt Forge.Jwt.Expired) -> "expired"
  in
  [
    Alcotest.test_case "verify" `Quick (fun () ->
        Alcotest.(check (list string))
          "outcomes"
          [ "ok ann"; "bad signature"; "expired"; "malformed"; "bad signature" ]
          (List.map outcome
             [
               Forge.Jwt.verify ~secret:"s" ~now:1010. token;
               Forge.Jwt.verify ~secret:"other" ~now:1010. token;
               Forge.Jwt.verify ~secret:"s" ~now:1061. token;
               Forge.Jwt.verify ~secret:"s" ~now:1010. "nope";
               Forge.Jwt.verify ~secret:"s" ~now:1010. (token ^ "x");
             ]));
    Alcotest.test_case "bearer guard and a role check" `Quick (fun () ->
        let fresh = Forge.Jwt.sign ~secret:"s" ~expires_in:60. "ann" in
        let admin =
          Forge.Guard.check
            (fun (claims : Forge.Jwt.claims) ->
              match claims.subject with
              | "root" -> Ok `Admin
              | _ -> Error (Forge.Error.forbidden "admins only"))
            (Forge.Jwt.bearer ~secret:"s")
        in
        let code guard headers =
          Result.fold
            ~ok:(fun _ -> "ok")
            ~error:(fun (error : Forge.Error.t) -> error.code)
            (Lwt_main.run (guard (Dream.request ~headers "")))
        in
        Alcotest.(check (list string))
          "codes"
          [ "ok"; "unauthorized"; "forbidden" ]
          [
            code
              (Forge.Jwt.bearer ~secret:"s")
              [ ("Authorization", "Bearer " ^ fresh) ];
            code (Forge.Jwt.bearer ~secret:"s") [];
            code admin [ ("Authorization", "Bearer " ^ fresh) ];
          ]);
  ]

let cron =
  let next expression after =
    Option.map int_of_float
      (Forge_shared.Cron.next
         (Result.get_ok (Forge_shared.Cron.of_string expression))
         ~after)
  in
  [
    Alcotest.test_case "next fire time in UTC" `Quick (fun () ->
        Alcotest.(check (list (option int)))
          "times"
          [ Some 1704079800; Some 1704672000; Some 1704067500; None ]
          [
            next "30 3 * * *" 1704067200.;
            next "0 0 * * 1" 1704067200.;
            next "*/5 * * * *" 1704067200.;
            next "0 0 31 2 *" 1704067200.;
          ]);
    Alcotest.test_case "parse errors" `Quick (fun () ->
        Alcotest.(check (list string))
          "errors"
          [
            "minute 61 is outside 0-59";
            "a cron expression has five fields: minute hour day month weekday";
            "hour range 5-2 is backwards";
          ]
          (List.map
             (fun expression ->
               Result.fold
                 ~ok:(fun _ -> "ok")
                 ~error:Fun.id
                 (Forge_shared.Cron.of_string expression))
             [ "61 * * * *"; "* * *"; "0 5-2 * * *" ]));
  ]

let cache =
  [
    Alcotest.test_case "memoize: ttl and evict" `Quick (fun () ->
        let now = ref 0. in
        let calls = ref 0 in
        let square =
          Forge.Cache.memoize ~ttl:10.
            ~clock:(fun () -> !now)
            (fun n ->
              incr calls;
              Lwt.return (n * n))
        in
        let ask n = Lwt_main.run (square.find n) in
        let first = ask 3 in
        let cached = ask 3 in
        now := 11.;
        let expired = ask 3 in
        square.evict 3;
        let evicted = ask 3 in
        Alcotest.(check (pair (list int) int))
          "values and calls"
          ([ 9; 9; 9; 9 ], 3)
          ([ first; cached; expired; evicted ], !calls));
  ]

let () =
  Alcotest.run "forge"
    [
      ("Cache", cache);
      ("Cron", cron);
      ("Jwt", jwt);
      ("Security", security);
      ("Migration", migration);
      ("Validation", validation);
      ("Scalar", scalar);
      ("Json", json_tests);
      ("Refined", refined);
      ("Error", error);
      ("Guard", guard);
      ("Spec", spec);
      ("App", app_tests);
    ]

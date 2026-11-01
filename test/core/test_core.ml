open Kre_shared

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
               ("type", `String "urn:kre:error:validation");
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
          (Kre.Error.to_json ~instance:"/cats"
             (Kre.Error.unprocessable
                (Validation.fail ~rule:"range" "must be between 0 and 40"))));
    Alcotest.test_case "to_response" `Quick (fun () ->
        let response =
          Dream.test
            (fun request ->
              Kre.Error.to_response request (Kre.Error.conflict "taken"))
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
            (Kre.Guard.both
               (Kre.Guard.field user ~missing:(Kre.Error.unauthorized "login"))
               (Kre.Guard.header "X-Key") request)
        in
        Alcotest.(check (result (pair string string) reject))
          "both"
          (Ok ("tom", "k"))
          (Result.map_error ignore guarded));
    Alcotest.test_case "missing field" `Quick (fun () ->
        let guarded =
          Lwt_main.run
            (Kre.Guard.field user
               ~missing:(Kre.Error.unauthorized "login")
               (get "/"))
        in
        Alcotest.(check (option string))
          "code" (Some "unauthorized")
          (Option.map
             (fun (e : Kre.Error.t) -> e.code)
             (Result.fold ~ok:(fun _ -> None) ~error:Option.some guarded)));
  ]

let cats = [ { Cat.id = 1; name = "tom" }; { Cat.id = 2; name = "felix" } ]

let admin : unit Kre.Guard.t =
 fun request ->
  Lwt.return
    (Option.fold
       ~none:(Error (Kre.Error.forbidden "admin only"))
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
  Kre.Controller.v ~middleware:[ tag ]
    ~spec:{ Kre.Spec.prefix = "/cats"; version = None; routes = [] }
    [
      Kre.Route.v `GET
        Routes.(
          (s "cats" /? nil)
          @--> Kre.Route.handle ~status:`OK
                 (Kre.Route.Json (module Json.List (Cat)))
                 (fun _ -> Lwt.return_ok cats));
      Kre.Route.v `GET
        Routes.(
          (s "cats" / int /? nil) @--> fun id ->
          Kre.Route.handle ~status:`OK
            (Kre.Route.Found (module Cat))
            (fun _ ->
              Lwt.return_ok (List.find_opt (fun (c : Cat.t) -> c.id = id) cats)));
      Kre.Route.v `POST
        Routes.(
          (s "cats" /? nil)
          @--> Kre.Route.handle ~status:`Created ~guards:[ admin ]
                 Kre.Route.Text (fun _ -> Lwt.return_ok "created"));
      Kre.Route.v `DELETE
        Routes.(
          (s "cats" / int /? nil) @--> fun _ ->
          Kre.Route.handle ~status:`No_Content Kre.Route.Unit (fun _ ->
              failwith "boom"));
      Kre.Route.v `PUT
        Routes.(
          (s "cats" / int /? nil) @--> fun _ ->
          Kre.Route.handle ~status:`OK Kre.Route.Unit (fun _ ->
              Kre.Error.fail (Kre.Error.conflict "locked")));
    ]

let app = Dream.test (Kre.App.handler [ controller ])

let app_tests =
  [
    Alcotest.test_case "empty app answers 404 Problem Details" `Quick (fun () ->
        let response = Dream.test (Kre.App.handler []) (get "/anything") in
        Alcotest.(check (pair int json))
          "404"
          ( 404,
            `Assoc
              [
                ("type", `String "urn:kre:error:not_found");
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
            (Kre.App.handler
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
                                           `String "Kre_shared.Scalar.Int" );
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
                         ("live", `List []);
                       ];
                   ] );
             ])
          (Kre.Spec.to_json
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
                               module_ = "Kre_shared.Scalar.Int";
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
                     live = [];
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
             (fun (m : Kre.Migration.t) -> (m.up, m.down))
             (Kre.Migration.parse ~version:"0001_a"
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
               Result.map ignore (Kre.Migration.parse ~version:"0001_a" text))
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
            (Kre.Cors.middleware ~origins:(Kre.Cors.Only [ "https://cats.io" ])
               () ok_handler)
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
            (Kre.Secure_headers.middleware () (fun _ ->
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
            (Kre.Rate_limit.middleware ~limit:2 ~window:10.
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
  let token = Kre.Jwt.sign ~secret:"s" ~now:1000. ~expires_in:60. "ann" in
  let outcome = function
    | Ok (claims : Kre.Jwt.claims) -> "ok " ^ claims.subject
    | Error (`Jwt Kre.Jwt.Malformed) -> "malformed"
    | Error (`Jwt Kre.Jwt.Bad_signature) -> "bad signature"
    | Error (`Jwt Kre.Jwt.Expired) -> "expired"
  in
  [
    Alcotest.test_case "verify" `Quick (fun () ->
        Alcotest.(check (list string))
          "outcomes"
          [ "ok ann"; "bad signature"; "expired"; "malformed"; "bad signature" ]
          (List.map outcome
             [
               Kre.Jwt.verify ~secret:"s" ~now:1010. token;
               Kre.Jwt.verify ~secret:"other" ~now:1010. token;
               Kre.Jwt.verify ~secret:"s" ~now:1061. token;
               Kre.Jwt.verify ~secret:"s" ~now:1010. "nope";
               Kre.Jwt.verify ~secret:"s" ~now:1010. (token ^ "x");
             ]));
    Alcotest.test_case "bearer guard and a role check" `Quick (fun () ->
        let fresh = Kre.Jwt.sign ~secret:"s" ~expires_in:60. "ann" in
        let admin =
          Kre.Guard.check
            (fun (claims : Kre.Jwt.claims) ->
              match claims.subject with
              | "root" -> Ok `Admin
              | _ -> Error (Kre.Error.forbidden "admins only"))
            (Kre.Jwt.bearer ~secret:"s")
        in
        let code guard headers =
          Result.fold
            ~ok:(fun _ -> "ok")
            ~error:(fun (error : Kre.Error.t) -> error.code)
            (Lwt_main.run (guard (Dream.request ~headers "")))
        in
        Alcotest.(check (list string))
          "codes"
          [ "ok"; "unauthorized"; "forbidden" ]
          [
            code
              (Kre.Jwt.bearer ~secret:"s")
              [ ("Authorization", "Bearer " ^ fresh) ];
            code (Kre.Jwt.bearer ~secret:"s") [];
            code admin [ ("Authorization", "Bearer " ^ fresh) ];
          ]);
  ]

let cron =
  let next expression after =
    Option.map int_of_float
      (Kre_shared.Cron.next
         (Result.get_ok (Kre_shared.Cron.of_string expression))
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
                 (Kre_shared.Cron.of_string expression))
             [ "61 * * * *"; "* * *"; "0 5-2 * * *" ]));
  ]

let cache =
  [
    Alcotest.test_case "memoize: ttl and evict" `Quick (fun () ->
        let now = ref 0. in
        let calls = ref 0 in
        let square =
          Kre.Cache.memoize ~ttl:10.
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

let live =
  [
    Alcotest.test_case "writes reach subscribers of that table" `Quick
      (fun () ->
        let changes, stop = Kre.Live.subscribe [ "cats" ] in
        List.iter Kre.Live.wrote
          [
            "INSERT INTO cats (name) VALUES (?)";
            "UPDATE `shop`.`cats` SET name = ?";
            "DELETE FROM dogs WHERE id = ?";
            "SELECT * FROM cats";
            "CREATE TABLE cats (id INT)";
          ];
        stop ();
        Alcotest.(check (list string))
          "changes" [ "cats"; "cats" ]
          (Lwt_stream.get_available changes));
    Alcotest.test_case "a transaction publishes on Ok, after it ends" `Quick
      (fun () ->
        let changes, stop = Kre.Live.subscribe [ "cats" ] in
        let during = ref [] in
        let run result =
          ignore
            (Lwt_main.run
               (Kre.Live.deferred (fun () ->
                    Kre.Live.wrote "INSERT INTO cats VALUES (1)";
                    during := !during @ Lwt_stream.get_available changes;
                    Lwt.return result)))
        in
        run (Error ());
        run (Ok ());
        stop ();
        Alcotest.(check (pair (list string) (list string)))
          "held, then published once" ([], [ "cats" ])
          (!during, Lwt_stream.get_available changes));
    Alcotest.test_case "[@@live] must list every table the route reads" `Quick
      (fun () ->
        Unix.putenv "KRE_ENV" "test";
        let answer tables =
          Dream.status
            (Dream.test
               (Kre.Live.audit tables (fun _ ->
                    Kre.Live.read
                      "SELECT c.name FROM (SELECT * FROM cats) c JOIN `users` \
                       u ON u.id = c.owner";
                    Dream.html "ok"))
               (Dream.request "/"))
        in
        let statuses =
          List.map
            (fun tables -> Dream.status_to_int (answer tables))
            [ [ "cats" ]; [ "cats"; "users" ] ]
        in
        Unix.putenv "KRE_ENV" "dev";
        Alcotest.(check (list int)) "statuses" [ 500; 200 ] statuses);
  ]

let table =
  let users =
    Kre.Table.make ~name:"users"
      [ Kre.Table.column ~role:Primary_auto "id" Integer Not_null ]
  in
  [
    Alcotest.test_case "crud: finders by unique, index and reference" `Quick
      (fun () ->
        Alcotest.(check string)
          "sql"
          "-- @all\n\
           SELECT id, email, team, owner_id FROM pets;\n\
           -- @insert\n\
           INSERT INTO pets (email, team, owner_id) VALUES (@email, @team, \
           @owner_id);\n\
           -- @find\n\
           SELECT id, email, team, owner_id FROM pets WHERE id = @id;\n\
           -- @update\n\
           UPDATE pets SET email = @email, team = @team, owner_id = @owner_id \
           WHERE id = @id;\n\
           -- @delete\n\
           DELETE FROM pets WHERE id = @id;\n\
           -- @page\n\
           SELECT id, email, team, owner_id FROM pets ORDER BY id LIMIT @limit \
           OFFSET @offset;\n\
           -- @by_email\n\
           SELECT id, email, team, owner_id FROM pets WHERE email = @email;\n\
           -- @by_team\n\
           SELECT id, email, team, owner_id FROM pets WHERE team = @team ORDER \
           BY id;\n\
           -- @by_owner_id\n\
           SELECT id, email, team, owner_id FROM pets WHERE owner_id = \
           @owner_id ORDER BY id;\n\
           -- @count\n\
           SELECT COUNT(*) FROM pets;\n"
          (Kre.Table.crud
             (Kre.Table.make ~name:"pets"
                [
                  Kre.Table.column ~role:Primary_auto "id" Integer Not_null;
                  Kre.Table.column ~role:Unique "email" (Text (Some 255))
                    Not_null;
                  Kre.Table.column ~role:Index "team" (Text None) Not_null;
                  Kre.Table.column ~references:users "owner_id" Integer Null;
                ])));
  ]

let etag =
  let handler =
    Dream.test
      (Kre.Etag.middleware (fun request ->
           match Dream.target request with
           | "/missing" -> Dream.empty `Not_Found
           | _ -> Dream.html "hello"))
  in
  let get ?(headers = []) target =
    let response = handler (Dream.request ~target ~headers "") in
    ( Dream.status_to_int (Dream.status response),
      Option.value ~default:"-" (Dream.header response "ETag"),
      Lwt_main.run (Dream.body response) )
  in
  [
    Alcotest.test_case "a repeated GET gets 304" `Quick (fun () ->
        let status, tag, body = get "/" in
        Alcotest.(check (list (triple int string string)))
          "responses"
          [
            (200, tag, "hello");
            (304, tag, "");
            (304, tag, "");
            (200, tag, "hello");
          ]
          [
            (status, tag, body);
            get ~headers:[ ("If-None-Match", tag) ] "/";
            get ~headers:[ ("If-None-Match", "\"old\", W/" ^ tag) ] "/";
            get ~headers:[ ("If-None-Match", "\"old\"") ] "/";
          ]);
    Alcotest.test_case "only 200 gets a tag" `Quick (fun () ->
        Alcotest.(check (triple int string string))
          "404" (404, "-", "") (get "/missing"));
  ]

let retry =
  let flaky failures =
    let calls = ref 0 in
    ( calls,
      fun () ->
        incr calls;
        match !calls <= failures with
        | true -> Lwt.fail (Failure (Printf.sprintf "call %d" !calls))
        | false -> Lwt.return !calls )
  in
  let outcome promise =
    Lwt_main.run
      (Lwt.catch
         (fun () -> Lwt.map (Printf.sprintf "ok %d") promise)
         (fun exn -> Lwt.return (Printexc.to_string exn)))
  in
  [
    Alcotest.test_case "retries until it succeeds" `Quick (fun () ->
        let calls, f = flaky 2 in
        let result = outcome (Kre.Retry.run ~backoff:0.001 ~attempts:3 f) in
        Alcotest.(check (pair string int))
          "third call" ("ok 3", 3) (result, !calls));
    Alcotest.test_case "gives up with the last exception" `Quick (fun () ->
        let calls, f = flaky 5 in
        let result = outcome (Kre.Retry.run ~attempts:2 f) in
        Alcotest.(check (pair string int))
          "two calls" ({|Failure("call 2")|}, 2) (result, !calls));
  ]

let command =
  let ran = ref [] in
  let greet =
    Kre.Command.make ~name:"greet" ~doc:"Say hello" ~options:[ "name"; "times" ]
      (fun args ->
        let open Kre_shared.Validation.Syntax in
        let+ name =
          Kre.Command.required (module Kre_shared.Scalar.String) "name" args
        and+ times =
          Kre.Command.optional
            (module Kre_shared.Scalar.Int)
            "times" ~default:1 args
        in
        fun () ->
          ran := Printf.sprintf "%s x%d" name times :: !ran;
          Lwt.return_unit)
  in
  let outcome arguments =
    match Kre.Command.invoke [ greet ] arguments with
    | Serve -> "serve"
    | Usage text -> text
    | Invalid message -> "invalid: " ^ message
    | Run run ->
        Lwt_main.run (run ());
        "ran " ^ String.concat "," !ran
  in
  [
    Alcotest.test_case "options and errors" `Quick (fun () ->
        Alcotest.(check (list string))
          "outcomes"
          [
            "serve";
            "serve";
            "ran ann x1";
            "ran bob x3,ann x1";
            "invalid: --name is required\n--times: must be an integer";
            "invalid: --size needs a value";
            "invalid: greet has no option --size\n\
             commands:\n\
            \  greet --name --times  Say hello\n";
            "commands:\n  greet --name --times  Say hello\n";
          ]
          (List.map outcome
             [
               [];
               [ "--port"; "1" ];
               [ "greet"; "--name"; "ann" ];
               [ "greet"; "--name=bob"; "--times"; "3" ];
               [ "greet"; "--times"; "x" ];
               [ "greet"; "--size" ];
               [ "greet"; "--size"; "1" ];
               [ "help" ];
             ]));
  ]

let page =
  let decode query =
    Result.fold
      ~ok:(fun (request : Kre_shared.Page.Request.t) ->
        Printf.sprintf "%d/%d from %d" request.page request.size
          (Kre_shared.Page.Request.offset request))
      ~error:(fun errors ->
        String.concat ","
          (List.map
             (fun (error : Kre_shared.Validation.error) ->
               String.concat "." error.path ^ ":" ^ error.rule)
             (Kre_shared.Validation.to_list errors)))
      (Kre_shared.Search.decode Kre_shared.Page.Request.codec query)
  in
  [
    Alcotest.test_case "a page request parses and checks" `Quick (fun () ->
        Alcotest.(check (list string))
          "requests"
          [ "1/20 from 0"; "3/10 from 20"; "page:min,size:range" ]
          [
            decode [];
            decode [ ("page", "3"); ("size", "10") ];
            decode [ ("page", "0"); ("size", "500") ];
          ]);
    Alcotest.test_case "a page in JSON" `Quick (fun () ->
        let module Pages = Kre_shared.Page.Make (Kre_shared.Scalar.String) in
        let page =
          Kre_shared.Page.make
            (Result.get_ok (Kre_shared.Page.Request.make ~page:2 ~size:2))
            ~total:5 [ "c"; "d" ]
        in
        Alcotest.(check (pair string int))
          "json and pages"
          ({|{"items":["c","d"],"page":2,"size":2,"total":5}|}, 3)
          (Jsonkit.to_string (Pages.to_json page), Kre_shared.Page.pages page));
  ]

let time =
  let show text =
    Result.fold ~ok:Kre_shared.Time.to_string
      ~error:(fun _ -> "invalid")
      (Kre_shared.Time.of_string text)
  in
  [
    Alcotest.test_case "RFC 3339 both ways" `Quick (fun () ->
        Alcotest.(check (list string))
          "times"
          [
            "1970-01-01T00:00:00.000Z";
            "1969-12-31T23:59:59.000Z";
            "2000-02-29T12:34:56.789Z";
            "2026-11-01T06:44:08.000Z";
            "2026-11-01T06:44:08.000Z";
            "invalid";
            "invalid";
            "invalid";
          ]
          [
            Kre_shared.Time.to_string (Kre_shared.Time.of_seconds 0.);
            Kre_shared.Time.to_string (Kre_shared.Time.of_seconds (-1.));
            show "2000-02-29T12:34:56.789Z";
            show "2026-11-01T09:44:08+03:00";
            show "2026-11-01 06:44:08z";
            show "2026-13-01T00:00:00Z";
            show "2026-11-01T06:44:08";
            show "yesterday";
          ]);
  ]

let profiler =
  [
    Alcotest.test_case "requests, their SQL and N+1" `Quick (fun () ->
        let handler =
          Dream.test
            (Kre.App.handler
               ~middleware:[ Kre.Profiler.middleware ]
               [
                 Kre.Profiler.controller;
                 Kre.Controller.v
                   ~spec:
                     {
                       Kre.Spec.prefix = "/owners";
                       version = None;
                       routes = [];
                     }
                   [
                     Kre.Route.v `GET
                       (Routes.( @--> )
                          Routes.(s "owners" /? nil)
                          (Kre.Route.handle ~status:`OK Kre.Route.Text (fun _ ->
                               Kre.Profiler.sql "SELECT * FROM owners";
                               List.iter
                                 (fun _ ->
                                   Kre.Profiler.sql
                                     "SELECT * FROM cats WHERE owner_id = ?")
                                 [ 1; 2; 3 ];
                               Lwt.return_ok "ok")));
                   ];
               ])
        in
        let get target =
          let response = handler (Dream.request ~target "") in
          ( Dream.status_to_int (Dream.status response),
            Lwt_main.run (Dream.body response) )
        in
        ignore (get "/owners");
        let entry = List.hd (Kre.Profiler.recent ()) in
        Alcotest.(check (triple string int (list (pair string int))))
          "entry"
          ("/owners", 4, [ ("SELECT * FROM cats WHERE owner_id = ?", 3) ])
          (entry.target, List.length entry.queries, Kre.Profiler.repeated entry);
        Alcotest.(check int) "page" 200 (fst (get "/__kre/profiler")));
  ]

let mail =
  let email text = Result.get_ok (Kre_shared.Refined.Email.of_repr text) in
  let letter =
    Kre.Mail.make
      ~from:(email "shelter@cats.test")
      ~to_:(email "ann@cats.test")
      ~cc:[ email "staff@cats.test" ]
      ~subject:"Привет" ~text:"Tom is yours.\n.dot line"
      ~html:"<p>Tom is yours.</p>" ()
  in
  [
    Alcotest.test_case "SMTP conversation" `Quick (fun () ->
        let socket = Lwt_unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
        Lwt_main.run
          (Lwt_unix.bind socket (Unix.ADDR_INET (Unix.inet_addr_loopback, 0)));
        Lwt_unix.listen socket 1;
        let port =
          match Lwt_unix.getsockname socket with
          | Unix.ADDR_INET (_, port) -> port
          | Unix.ADDR_UNIX _ -> 0
        in
        let commands = ref [] and data = ref [] in
        let server =
          let%lwt client, _ = Lwt_unix.accept socket in
          let input = Lwt_io.of_fd ~mode:Lwt_io.input client in
          let output = Lwt_io.of_fd ~mode:Lwt_io.output client in
          let say text = Lwt_io.write output (text ^ "\r\n") in
          let%lwt () = say "220 fake" in
          let rec serve () =
            let%lwt line = Lwt_io.read_line input in
            let line = String.trim line in
            commands := line :: !commands;
            match String.split_on_char ' ' line with
            | "EHLO" :: _ ->
                let%lwt () = say "250-fake" in
                let%lwt () = say "250 OK" in
                serve ()
            | "DATA" :: _ ->
                let%lwt () = say "354 go" in
                let rec body () =
                  let%lwt line = Lwt_io.read_line input in
                  match String.trim line with
                  | "." -> say "250 queued"
                  | line ->
                      data := line :: !data;
                      body ()
                in
                let%lwt () = body () in
                serve ()
            | "QUIT" :: _ -> say "221 bye"
            | _ ->
                let%lwt () = say "250 OK" in
                serve ()
          in
          let%lwt () = serve () in
          Lwt_io.close output
        in
        let module Smtp = Kre.Mail.Smtp (struct
          let host = "127.0.0.1"
          let port = port
          let helo = "kre.test"
        end) in
        let sent = Lwt_main.run (Smtp.send letter) in
        Lwt_main.run server;
        Alcotest.(check (result unit string)) "sent" (Ok ()) sent;
        Alcotest.(check (list string))
          "commands"
          [
            "EHLO kre.test";
            "MAIL FROM:<shelter@cats.test>";
            "RCPT TO:<ann@cats.test>";
            "RCPT TO:<staff@cats.test>";
            "DATA";
            "QUIT";
          ]
          (List.rev !commands);
        let body = List.rev !data in
        Alcotest.(check (list bool))
          "headers, dot-stuffing, both parts" [ true; true; true; true ]
          [
            List.mem "Subject: =?UTF-8?B?0J/RgNC40LLQtdGC?=" body;
            List.mem "..dot line" body;
            List.mem "Content-Type: text/html; charset=utf-8" body;
            List.mem "Cc: staff@cats.test" body;
          ]);
    Alcotest.test_case "outbox keeps letters" `Quick (fun () ->
        let module Outbox = Kre.Mail.Outbox () in
        ignore (Lwt_main.run (Outbox.send letter));
        Alcotest.(check (list string))
          "subjects" [ "Привет" ]
          (List.map
             (fun (letter : Kre.Mail.t) -> letter.subject)
             (Outbox.sent ())));
  ]

let assets =
  let dir = Filename.concat (Filename.get_temp_dir_name ()) "kre-assets-test" in
  (try Sys.mkdir dir 0o755 with Sys_error _ -> ());
  Out_channel.with_open_bin (Filename.concat dir "logo.svg") (fun out ->
      Out_channel.output_string out "<svg/>");
  let hash = String.sub (Digest.to_hex (Digest.string "<svg/>")) 0 8 in
  let handler =
    Dream.test (Kre.Assets.middleware ~dir (fun _ -> Dream.empty `Not_Found))
  in
  let get target =
    let response = handler (Dream.request ~target "") in
    ( Dream.status_to_int (Dream.status response),
      Option.value ~default:"-" (Dream.header response "Cache-Control") )
  in
  [
    Alcotest.test_case "hashed URL, stale hash, traversal" `Quick (fun () ->
        Alcotest.(check (list (pair int string)))
          "responses"
          [
            (200, "public, max-age=31536000, immutable"); (404, "-"); (404, "-");
          ]
          (List.map get
             [
               "/assets/logo." ^ hash ^ ".svg";
               "/assets/logo.deadbeef.svg";
               "/assets/../logo." ^ hash ^ ".svg";
             ]));
  ]

let () =
  Alcotest.run "kre"
    [
      ("Live", live);
      ("Table", table);
      ("Etag", etag);
      ("Retry", retry);
      ("Command", command);
      ("Page", page);
      ("Time", time);
      ("Profiler", profiler);
      ("Mail", mail);
      ("Assets", assets);
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

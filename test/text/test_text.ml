let verdict rules text =
  Result.fold
    ~ok:(fun _ -> "ok")
    ~error:(fun (errors : Kre_shared.Validation.t) -> errors.first.rule)
    (Kre_shared.Validation.check rules text)

let native =
  List.map
    (verdict Kre_shared.Validation.[ min_length 2; max_length 3 ])
    [
      "cat";
      "Zo\xc3\xab";
      "\xe6\x97\xa5\xe6\x9c\xac";
      "\xf0\x9f\x90\x88";
      "\xf0\x9f\x90\x88\xf0\x9f\x90\x88";
      "cats";
    ]
  @ List.map
      (fun (source, text) ->
        verdict [ Kre_shared.Validation.pattern source ] text)
      [
        ("^[a-z0-9-]+$", "tom-1");
        ("^[a-z0-9-]+$", "Tom");
        ("^\\d{3}$", "123");
        ("^\\d{3}$", "12");
        ("a(", "a");
      ]

let expected =
  [
    "ok";
    "ok";
    "ok";
    "min_length";
    "ok";
    "max_length";
    "ok";
    "pattern";
    "ok";
    "pattern";
    "pattern";
  ]

module Slug = Kre_shared.Refined.Pattern (struct
  let name = "slug"
  let pattern = "^[a-z0-9-]+$"
end)

let () =
  Alcotest.run "text"
    [
      ( "the server and the browser agree",
        [
          Alcotest.test_case "native" `Quick (fun () ->
              Alcotest.(check (list string)) "verdicts" expected native);
          Alcotest.test_case "melange, in node" `Quick (fun () ->
              Alcotest.(check (list string))
                "verdicts" expected
                (String.split_on_char '\n'
                   (String.trim
                      (In_channel.input_all
                         (Unix.open_process_args_in
                            (Option.value (Sys.getenv_opt "NODE")
                               ~default:"node")
                            [| "node"; "js/test/text/text_check.js" |])))));
        ] );
      ( "Refined.Pattern",
        [
          Alcotest.test_case "rule and schema" `Quick (fun () ->
              Alcotest.(check (list string))
                "slug"
                [ "tom-1"; "must match ^[a-z0-9-]+$"; {|"^[a-z0-9-]+$"|} ]
                [
                  Result.fold ~ok:Slug.to_repr
                    ~error:(fun (errors : Kre_shared.Validation.t) ->
                      errors.first.message)
                    (Slug.of_repr "tom-1");
                  Result.fold ~ok:Slug.to_repr
                    ~error:(fun (errors : Kre_shared.Validation.t) ->
                      errors.first.message)
                    (Slug.of_repr "Tom");
                  Yojson.Basic.to_string
                    (Yojson.Basic.Util.member "pattern" Slug.t_jsonschema);
                ]);
        ] );
    ]

let samples =
  [
    "cat";
    "Zo\xc3\xab";
    "\xe6\x97\xa5\xe6\x9c\xac";
    "\xf0\x9f\x90\x88";
    "\xf0\x9f\x90\x88\xf0\x9f\x90\x88";
    "cats";
  ]

let expected = [ "ok"; "ok"; "ok"; "min_length"; "ok"; "max_length" ]

let () =
  Alcotest.run "text"
    [
      ( "length counts characters",
        [
          Alcotest.test_case "native" `Quick (fun () ->
              Alcotest.(check (list string))
                "verdicts" expected
                (List.map
                   (fun text ->
                     Result.fold
                       ~ok:(fun _ -> "ok")
                       ~error:(fun (errors : Kre_shared.Validation.t) ->
                         errors.first.rule)
                       (Kre_shared.Validation.check
                          Kre_shared.Validation.[ min_length 2; max_length 3 ]
                          text))
                   samples));
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
    ]

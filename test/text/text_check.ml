let () =
  List.iter
    (fun text ->
      print_endline
        (Result.fold
           ~ok:(fun _ -> "ok")
           ~error:(fun (errors : Kre_shared.Validation.t) -> errors.first.rule)
           (Kre_shared.Validation.check
              Kre_shared.Validation.[ min_length 2; max_length 3 ]
              text)))
    [
      {js|cat|js}; {js|Zoë|js}; {js|日本|js}; {js|🐈|js}; {js|🐈🐈|js}; {js|cats|js};
    ]

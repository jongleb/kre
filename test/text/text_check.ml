let verdict rules text =
  Result.fold
    ~ok:(fun _ -> "ok")
    ~error:(fun (errors : Kre_shared.Validation.t) -> errors.first.rule)
    (Kre_shared.Validation.check rules text)

let () =
  List.iter
    (fun text ->
      print_endline
        (verdict Kre_shared.Validation.[ min_length 2; max_length 3 ] text))
    [
      {js|cat|js}; {js|Zoë|js}; {js|日本|js}; {js|🐈|js}; {js|🐈🐈|js}; {js|cats|js};
    ];
  List.iter
    (fun (source, text) ->
      print_endline (verdict [ Kre_shared.Validation.pattern source ] text))
    [
      ("^[a-z0-9-]+$", "tom-1");
      ("^[a-z0-9-]+$", "Tom");
      ("^\\d{3}$", "123");
      ("^\\d{3}$", "12");
      ("a(", "a");
    ]

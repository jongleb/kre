type 's t = {
  parse : (string * string) list -> ('s, Validation.t) result;
  print : 's -> (string * string) list list;
}

type ('a, 'b) presence =
  | Required : ('a, 'a) presence
  | Optional : ('a, 'a option) presence
  | Default : 'a -> ('a, 'a) presence
  | Repeated : ('a, 'a list) presence

type 'a field = {
  read : (string * string) list -> ('a, Validation.t) result;
  show : 'a -> (string * string) list;
}

let none = { parse = (fun _ -> Ok ()); print = (fun () -> []) }

let field (type b) name (module S : Scalar.S) (presence : (S.t, b) presence) :
    b field =
  let parse raw = Result.map_error (Validation.at [ name ]) (S.of_string raw) in
  let values pairs =
    List.filter_map
      (function
        | key, value when String.equal key name -> Some value | _ -> None)
      pairs
  in
  let one value = [ (name, S.to_string value) ] in
  match presence with
  | Required ->
      {
        read =
          (fun pairs ->
            match values pairs with
            | raw :: _ -> parse raw
            | [] ->
                Error
                  (Validation.at [ name ]
                     (Validation.fail ~rule:"missing" "required")));
        show = one;
      }
  | Optional ->
      {
        read =
          (fun pairs ->
            match values pairs with
            | raw :: _ -> Result.map Option.some (parse raw)
            | [] -> Ok None);
        show = (fun value -> Option.fold ~none:[] ~some:one value);
      }
  | Default default ->
      {
        read =
          (fun pairs ->
            match values pairs with raw :: _ -> parse raw | [] -> Ok default);
        show = one;
      }
  | Repeated ->
      {
        read =
          (fun pairs ->
            List.fold_right
              (fun raw parsed ->
                Result.bind (parse raw) (fun value ->
                    Result.map (List.cons value) parsed))
              (values pairs) (Ok []));
        show = (fun values -> List.concat_map one values);
      }

let read field pairs = field.read pairs
let show field value = field.show value
let make ~parse ~print = { parse; print }
let decode search pairs = search.parse pairs
let encode search value = List.concat (search.print value)

type segment = Literal of string | Param of string

type 'p t = {
  segments : segment list;
  decode : (string * string) list -> ('p, Kre_shared.Validation.t) result;
  encode : 'p -> (string * string) list;
}

let parse pattern =
  List.filter_map
    (fun segment ->
      match String.split_on_char ':' segment with
      | [ "" ] -> None
      | [ ""; name ] -> Some (Param name)
      | _ -> Some (Literal segment))
    (String.split_on_char '/' pattern)

let static pattern =
  {
    segments = parse pattern;
    decode = (fun _ -> Ok ());
    encode = (fun () -> []);
  }

let make pattern ~decode ~encode = { segments = parse pattern; decode; encode }

let param (module S : Kre_shared.Scalar.S) name pairs =
  Option.fold
    ~none:(Error (Kre_shared.Validation.fail ~rule:"missing" ("no :" ^ name)))
    ~some:(fun raw ->
      Result.map_error (Kre_shared.Validation.at [ name ]) (S.of_string raw))
    (List.assoc_opt name pairs)

let match_ path url =
  match List.compare_lengths path.segments url with
  | 0 ->
      Option.bind
        (List.fold_left2
           (fun pairs segment value ->
             Option.bind pairs (fun pairs ->
                 match segment with
                 | Literal literal when String.equal literal value -> Some pairs
                 | Literal _ -> None
                 | Param name -> Some ((name, value) :: pairs)))
           (Some []) path.segments url)
        (fun pairs -> Result.to_option (path.decode pairs))
  | _ -> None

let print path params =
  let values = path.encode params in
  "/"
  ^ String.concat "/"
      (List.map
         (function
           | Literal literal -> literal
           | Param name ->
               Js.Global.encodeURIComponent
                 (Option.value (List.assoc_opt name values) ~default:""))
         path.segments)

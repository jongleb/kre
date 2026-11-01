type problem = {
  status : int;
  type_ : string;
  title : string;
  detail : string;
  errors : Kre_shared.Validation.error list;
}

type t =
  | Problem of problem
  | Network of string
  | Decode of Kre_shared.Validation.t

let of_response ~status body =
  let text json =
    match Jsonkit.classify json with `String s -> Some s | _ -> None
  in
  let items json =
    match Jsonkit.classify json with `List items -> items | _ -> []
  in
  let fields json =
    match Jsonkit.classify json with `Assoc fields -> fields | _ -> []
  in
  let problem =
    match Jsonkit.of_string body with
    | json -> fields json
    | exception Jsonkit.Of_string_error _ -> []
  in
  let member name fields = List.assoc_opt name fields in
  let string name fields ~default =
    Option.value (Option.bind (member name fields) text) ~default
  in
  Problem
    {
      status;
      type_ = string "type" problem ~default:"about:blank";
      title = string "title" problem ~default:"";
      detail = string "detail" problem ~default:body;
      errors =
        List.map
          (fun error ->
            let error = fields error in
            {
              Kre_shared.Validation.path =
                List.filter_map text
                  (Option.fold ~none:[] ~some:items (member "path" error));
              rule = string "rule" error ~default:"";
              message = string "message" error ~default:"";
            })
          (Option.fold ~none:[] ~some:items (member "errors" problem));
    }

let message = function
  | Problem { detail; _ } -> detail
  | Network message -> message
  | Decode errors ->
      String.concat "; "
        (List.map
           (fun (error : Kre_shared.Validation.error) -> error.message)
           (Kre_shared.Validation.to_list errors))

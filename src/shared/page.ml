type 'a t = { items : 'a list; page : int; size : int; total : int }

let integer name json =
  match Jsonkit.classify json with
  | `Assoc fields -> (
      match Option.map Jsonkit.classify (List.assoc_opt name fields) with
      | Some (`Int value) -> value
      | Some _ | None ->
          raise
            (Validation.Invalid
               (Validation.at [ name ]
                  (Validation.fail ~rule:"type" "must be an integer"))))
  | _ ->
      raise
        (Validation.Invalid (Validation.fail ~rule:"type" "must be an object"))

module Request = struct
  type t = { page : int; size : int }

  let make ~page ~size =
    let open Validation.Syntax in
    let+ page = Validation.field "page" [ Validation.min 1 ] page
    and+ size =
      Validation.field "size" [ Validation.range ~min:1 ~max:100 ] size
    in
    { page; size }

  let first = { page = 1; size = 20 }
  let offset request = (request.page - 1) * request.size

  let codec =
    let page =
      Search.field "page" (module Scalar.Int) (Search.Default first.page)
    in
    let size =
      Search.field "size" (module Scalar.Int) (Search.Default first.size)
    in
    Search.make
      ~parse:(fun pairs ->
        Result.bind
          (let open Validation.Syntax in
           let+ page = Search.read page pairs
           and+ size = Search.read size pairs in
           (page, size))
          (fun (page, size) -> make ~page ~size))
      ~print:(fun request ->
        [ Search.show page request.page; Search.show size request.size ])

  let of_json json =
    Validation.ok_exn
      (make ~page:(integer "page" json) ~size:(integer "size" json))

  let to_json request =
    Jsonkit.declassify
      (`Assoc
         [
           ("page", Jsonkit.declassify (`Int request.page));
           ("size", Jsonkit.declassify (`Int request.size));
         ])

  let t_jsonschema =
    `Assoc
      [
        ("type", `String "object");
        ( "properties",
          `Assoc
            [
              ( "page",
                `Assoc [ ("type", `String "integer"); ("minimum", `Int 1) ] );
              ( "size",
                `Assoc
                  [
                    ("type", `String "integer");
                    ("minimum", `Int 1);
                    ("maximum", `Int 100);
                  ] );
            ] );
      ]
end

let make (request : Request.t) ~total items =
  { items; page = request.page; size = request.size; total }

let pages page = (page.total + page.size - 1) / page.size

module Make (J : Json.S) = struct
  type nonrec t = J.t t

  let of_json json =
    {
      items =
        (match Jsonkit.classify json with
        | `Assoc fields ->
            Option.fold ~none:[]
              ~some:(fun items ->
                match Jsonkit.classify items with
                | `List items -> List.map J.of_json items
                | _ ->
                    raise
                      (Validation.Invalid
                         (Validation.at [ "items" ]
                            (Validation.fail ~rule:"type" "must be an array"))))
              (List.assoc_opt "items" fields)
        | _ -> []);
      page = integer "page" json;
      size = integer "size" json;
      total = integer "total" json;
    }

  let to_json page =
    Jsonkit.declassify
      (`Assoc
         [
           ("items", Jsonkit.declassify (`List (List.map J.to_json page.items)));
           ("page", Jsonkit.declassify (`Int page.page));
           ("size", Jsonkit.declassify (`Int page.size));
           ("total", Jsonkit.declassify (`Int page.total));
         ])

  let t_jsonschema =
    `Assoc
      [
        ("type", `String "object");
        ( "properties",
          `Assoc
            [
              ( "items",
                `Assoc [ ("type", `String "array"); ("items", J.t_jsonschema) ]
              );
              ("page", `Assoc [ ("type", `String "integer") ]);
              ("size", `Assoc [ ("type", `String "integer") ]);
              ("total", `Assoc [ ("type", `String "integer") ]);
            ] );
        ( "required",
          `List
            [ `String "items"; `String "page"; `String "size"; `String "total" ]
        );
      ]
end

let parse search query =
  Kre_shared.Search.decode search
    (List.filter_map
       (fun pair ->
         match String.split_on_char '=' pair with
         | [ "" ] -> None
         | [ key ] -> Some (Js.Global.decodeURIComponent key, "")
         | key :: value ->
             Some
               ( Js.Global.decodeURIComponent key,
                 Js.Global.decodeURIComponent (String.concat "=" value) )
         | [] -> None)
       (String.split_on_char '&'
          (match String.length query with
          | 0 -> ""
          | _ when query.[0] = '?' ->
              String.sub query 1 (String.length query - 1)
          | _ -> query)))

let print search value =
  match Kre_shared.Search.encode search value with
  | [] -> ""
  | pairs ->
      "?"
      ^ String.concat "&"
          (List.map
             (fun (key, value) ->
               Js.Global.encodeURIComponent key
               ^ "="
               ^ Js.Global.encodeURIComponent value)
             pairs)

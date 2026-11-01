type verb = [ `GET | `POST | `PUT | `PATCH | `DELETE | `HEAD | `OPTIONS ]
type response = { status : int; body : string }

type 'a returns =
  | Unit : unit returns
  | Text : string returns
  | Json : (module Kre_shared.Json.S with type t = 'a) -> 'a returns
  | Raw : response returns

let method_name = function
  | `GET -> "GET"
  | `POST -> "POST"
  | `PUT -> "PUT"
  | `PATCH -> "PATCH"
  | `DELETE -> "DELETE"
  | `HEAD -> "HEAD"
  | `OPTIONS -> "OPTIONS"

let encode text =
  String.concat ""
    (List.map
       (fun c ->
         match c with
         | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '-' | '_' | '.' | '~' ->
             String.make 1 c
         | c -> Printf.sprintf "%%%02X" (Char.code c))
       (List.init (String.length text) (String.get text)))

let segment (module S : Kre_shared.Scalar.S) value = encode (S.to_string value)

let query (type b) (module S : Kre_shared.Scalar.S)
    (presence : (S.t, b) Kre_shared.Presence.t) name (value : b) =
  List.map
    (fun value -> (name, S.to_string value))
    (match presence with
    | Required -> [ value ]
    | Optional -> Option.to_list value
    | Repeated -> value)

let body (module J : Kre_shared.Json.S) value =
  Jsonkit.to_string (J.to_json value)

let url ~base ~path ~query =
  base ^ "/" ^ String.concat "/" path
  ^
  match List.concat query with
  | [] -> ""
  | pairs ->
      "?"
      ^ String.concat "&"
          (List.map
             (fun (name, value) -> encode name ^ "=" ^ encode value)
             pairs)

let decode (type a) (returns : a returns) response : (a, Error.t) result =
  match response.status with
  | status when status >= 400 -> Error (Error.of_response ~status response.body)
  | _ -> (
      match returns with
      | Unit -> Ok ()
      | Text -> Ok response.body
      | Raw -> Ok response
      | Json (module J) -> (
          match Jsonkit.of_string response.body with
          | json ->
              Result.map_error
                (fun errors -> Error.Decode errors)
                (Kre_shared.Json.parse (module J) json)
          | exception Jsonkit.Of_string_error message ->
              Error
                (Error.Decode (Kre_shared.Validation.fail ~rule:"json" message))
          ))

let search codec value = Kre_shared.Search.encode codec value

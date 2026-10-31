type handler = Dream.request -> (Dream.response, Error.t) result Lwt.t

type t = {
  verb : Spec.verb;
  middleware : Dream.middleware list;
  target : handler Routes.route;
}

type 'a returns =
  | Unit : unit returns
  | Text : string returns
  | Json : (module Forge_shared.Json.S with type t = 'a) -> 'a returns
  | Found : (module Forge_shared.Json.S with type t = 'a) -> 'a option returns
  | Raw : Dream.response returns

let v ?(middleware = []) verb target = { verb; middleware; target }

let handle (type a) ~status ?(guards = []) (returns : a returns)
    (body : Dream.request -> (a, Error.t) result Lwt.t) request =
  let respond (value : a) =
    match returns with
    | Unit -> Lwt_result.ok (Dream.empty status)
    | Text ->
        Lwt_result.ok
          (Dream.respond ~status
             ~headers:[ ("Content-Type", "text/plain; charset=utf-8") ]
             value)
    | Json (module J) -> Lwt_result.ok (Response.json ~status (module J) value)
    | Found (module J) ->
        Option.fold
          ~none:(Lwt.return_error (Error.not_found "resource not found"))
          ~some:(fun found ->
            Lwt_result.ok (Response.json ~status (module J) found))
          value
    | Raw -> Lwt.return_ok value
  in
  Lwt.catch
    (fun () ->
      let open Lwt_result.Syntax in
      let* () =
        List.fold_left
          (fun checked guard ->
            Lwt_result.bind checked (fun () -> guard request))
          (Lwt.return_ok ()) guards
      in
      let* value = body request in
      respond value)
    (function
      | Error.E error -> Lwt.return_error error
      | exn ->
          Dream.error (fun log ->
              log ~request "unhandled exception: %s" (Printexc.to_string exn));
          Lwt.return_error (Error.internal "internal server error"))

let segment (module S : Forge_shared.Scalar.S) label path =
  Routes.pattern S.to_string
    (fun s -> Result.to_option (S.of_string s))
    label path

let query (type b) (module S : Forge_shared.Scalar.S)
    (presence : (S.t, b) Forge_shared.Presence.t) name request :
    (b, Error.t) result Lwt.t =
  let parse raw =
    Result.map_error
      (fun errors ->
        Error.bad_request
          ~extensions:
            [
              ( "errors",
                Forge_shared.Validation.to_json
                  (Forge_shared.Validation.at [ name ] errors) );
            ]
          ("invalid query parameter " ^ name))
      (S.of_string raw)
  in
  let parsed : (b, Error.t) result =
    match presence with
    | Required ->
        Option.fold
          ~none:(Error (Error.bad_request ("missing query parameter " ^ name)))
          ~some:parse (Dream.query request name)
    | Optional ->
        Option.fold ~none:(Ok None)
          ~some:(fun raw -> Result.map Option.some (parse raw))
          (Dream.query request name)
    | Repeated ->
        List.fold_right
          (fun raw parsed ->
            Result.bind (parse raw) (fun value ->
                Result.map (List.cons value) parsed))
          (Dream.queries request name)
          (Ok [])
  in
  Lwt.return parsed

let body (module J : Forge_shared.Json.S) request =
  Lwt.map
    (fun text ->
      match Jsonkit.of_string text with
      | json ->
          Result.map_error Error.unprocessable
            (Forge_shared.Json.parse (module J) json)
      | exception Jsonkit.Of_string_error message ->
          Error (Error.bad_request ("request body is not JSON: " ^ message)))
    (Dream.body request)

let ok promise = Lwt.map Result.ok promise

module Syntax = struct
  let ( let* ) promise next = Lwt_result.bind promise next
end

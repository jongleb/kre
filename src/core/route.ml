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

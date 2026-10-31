type init
type response

external init :
  method_:(string[@mel.as "method"]) ->
  headers:string Js.Dict.t ->
  ?body:string ->
  unit ->
  init = ""
[@@mel.obj]

external fetch : string -> init -> response Js.Promise.t = "fetch"
external status : response -> int = "status" [@@mel.get]
external text : response -> string Js.Promise.t = "text" [@@mel.send]

let base_url = ref ""
let headers = ref []

let request verb ~path ?(query = []) ?body returns =
  fetch
    (Wire.url ~base:!base_url ~path ~query)
    (init ~method_:(Wire.method_name verb)
       ~headers:
         (Js.Dict.fromList
            ((("Accept", "application/json") :: !headers)
            @ Option.fold ~none:[]
                ~some:(fun _ -> [ ("Content-Type", "application/json") ])
                body))
       ?body ())
  |> Js.Promise.then_ (fun response ->
      text response
      |> Js.Promise.then_ (fun body ->
          Js.Promise.resolve
            (Wire.decode returns { Wire.status = status response; body })))
  |> Js.Promise.catch (fun error ->
      Js.Promise.resolve (Error (Error.Network (Js.String.make error))))

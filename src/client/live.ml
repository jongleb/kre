type source
type message

external source : string -> source = "EventSource" [@@mel.new]

external on_message : source -> (message -> unit) -> unit = "onmessage"
[@@mel.set]

external data : message -> string = "data" [@@mel.get]
external close : source -> unit = "close" [@@mel.send]

let watch tables changed =
  let source =
    source
      (Wire.url ~base:!Http.base_url ~path:[ "__kre"; "live" ]
         ~query:[ List.map (fun table -> ("table", table)) tables ])
  in
  on_message source (fun message -> changed (data message));
  fun () -> close source

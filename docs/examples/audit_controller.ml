[@@@controller "audit"]
[@@@intercept [ Forge.Interceptor.logging ]]

let hidden =
  Forge.Interceptor.map_error (fun (error : Forge.Error.t) ->
      match error.code with
      | "not_found" -> Forge.Error.forbidden "hidden"
      | _ -> error)

let calls = ref 0

let counted =
  Forge.Interceptor.tap (fun _ ->
      incr calls;
      Lwt.return_unit)

let secret ~(id : int) : (string, Forge.Error.t) result Lwt.t =
  Lwt.return
    (match id with
    | 1 -> Ok "one"
    | _ -> Error (Forge.Error.not_found "secret"))
[@@get ":id"] [@@intercept [ hidden; counted ]]

let slow () : string Lwt.t =
  let%lwt () = Lwt_unix.sleep 1.0 in
  Lwt.return "late"
[@@get "slow"] [@@intercept [ Forge.Interceptor.timeout 0.05 ]]

[@@@controller "audit"]
[@@@intercept [ Kre.Interceptor.logging ]]

let hidden =
  Kre.Interceptor.map_error (fun (error : Kre.Error.t) ->
      match error.code with
      | "not_found" -> Kre.Error.forbidden "hidden"
      | _ -> error)

let calls = ref 0

let counted =
  Kre.Interceptor.tap (fun _ ->
      incr calls;
      Lwt.return_unit)

let secret ~(id : int) : (string, Kre.Error.t) result Lwt.t =
  Lwt.return
    (match id with 1 -> Ok "one" | _ -> Error (Kre.Error.not_found "secret"))
[@@get ":id"] [@@intercept [ hidden; counted ]]

let slow () : string Lwt.t =
  let%lwt () = Lwt_unix.sleep 1.0 in
  Lwt.return "late"
[@@get "slow"] [@@intercept [ Kre.Interceptor.timeout 0.05 ]]

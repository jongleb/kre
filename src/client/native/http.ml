let base_url = ref ""
let headers = ref []

let request verb ~path ?(query = []) ?headers:(extra = []) ?body returns =
  Lwt.catch
    (fun () ->
      let open Lwt.Syntax in
      let* response, response_body =
        Cohttp_lwt_unix.Client.call
          ~headers:
            (Cohttp.Header.of_list
               (("Accept", "application/json")
                :: (!headers @ List.concat extra)
               @ Option.fold ~none:[]
                   ~some:(fun _ -> [ ("Content-Type", "application/json") ])
                   body))
          ?body:(Option.map Cohttp_lwt.Body.of_string body)
          (verb :> Cohttp.Code.meth)
          (Uri.of_string (Wire.url ~base:!base_url ~path ~query))
      in
      let+ text = Cohttp_lwt.Body.to_string response_body in
      Wire.decode returns
        {
          Wire.status =
            Cohttp.Code.code_of_status (Cohttp.Response.status response);
          body = text;
        })
    (fun exn -> Lwt.return_error (Error.Network (Printexc.to_string exn)))

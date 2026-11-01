type exchange = {
  verb : Wire.verb;
  target : string;
  headers : (string * string) list;
  body : string option;
}

type transport = Network | Local of (exchange -> Wire.response Lwt.t)

let base_url = ref ""
let headers = ref []
let transport = ref Network

let request ?base verb ~path ?(query = []) ?headers:(extra = []) ?body returns =
  let sent =
    (("Accept", "application/json") :: (!headers @ List.concat extra))
    @ Option.fold ~none:[]
        ~some:(fun _ -> [ ("Content-Type", "application/json") ])
        body
  in
  Lwt.catch
    (fun () ->
      Lwt.map (Wire.decode returns)
        (match !transport with
        | Local handle ->
            handle
              {
                verb;
                target = Wire.url ~base:"" ~path ~query;
                headers = sent;
                body;
              }
        | Network ->
            let open Lwt.Syntax in
            let* response, response_body =
              Cohttp_lwt_unix.Client.call
                ~headers:(Cohttp.Header.of_list sent)
                ?body:(Option.map Cohttp_lwt.Body.of_string body)
                (verb :> Cohttp.Code.meth)
                (Uri.of_string
                   (Wire.url
                      ~base:(Option.value base ~default:!base_url)
                      ~path ~query))
            in
            let+ text = Cohttp_lwt.Body.to_string response_body in
            {
              Wire.status =
                Cohttp.Code.code_of_status (Cohttp.Response.status response);
              body = text;
            }))
    (fun exn -> Lwt.return_error (Error.Network (Printexc.to_string exn)))

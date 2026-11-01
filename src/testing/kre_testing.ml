let use ?middleware controllers =
  let handler = Kre.App.handler ?middleware controllers in
  Kre_client.Http.transport :=
    Local
      (fun exchange ->
        Lwt.bind
          (handler
             (Dream.request
                ~method_:(exchange.verb :> Dream.method_)
                ~target:exchange.target ~headers:exchange.headers
                (Option.value ~default:"" exchange.body)))
          (fun response ->
            Lwt.map
              (fun body ->
                {
                  Kre_client.Wire.status =
                    Dream.status_to_int (Dream.status response);
                  body;
                })
              (Dream.body response)))

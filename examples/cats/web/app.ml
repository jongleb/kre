let () =
  Forge_client.Http.headers := [ ("X-User", "web") ];
  Option.iter
    (fun root ->
      ReactDOM.Client.render
        (ReactDOM.Client.createRoot root)
        (React.createElement Forge_client.Router.View.make
           (Forge_client.Router.View.makeProps
              ~router:Cats_client_js.Routes.router
              ~pending:(React.string "Loading…")
              ())))
    (ReactDOM.querySelector "#root")

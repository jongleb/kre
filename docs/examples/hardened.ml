let middleware =
  [
    Forge.Secure_headers.middleware ();
    Forge.Cors.middleware ~origins:(Forge.Cors.Only [ "https://cats.example" ])
      ();
    Forge.Rate_limit.middleware ~limit:100 ~window:60. ();
  ]

let main () =
  Forge.App.run ~middleware [ Cats_controller.register (module Cats_service) ]

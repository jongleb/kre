let middleware =
  [
    Kre.Secure_headers.middleware ();
    Kre.Cors.middleware ~origins:(Kre.Cors.Only [ "https://cats.example" ]) ();
    Kre.Rate_limit.middleware ~limit:100 ~window:60. ();
  ]

let main () =
  Kre.App.run ~middleware [ Cats_controller.register (module Cats_service) ]

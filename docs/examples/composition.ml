let controllers ~fake =
  match fake with
  | `Fake -> [ Cats_controller.register (module Fake_cats) ]
  | `Real -> [ Cats_controller.register (module Cats_service) ]

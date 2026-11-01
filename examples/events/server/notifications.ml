module type S = sig
  val send : string -> string list
end

module Make (Notifiers : Kre.Wiring.ALL with type t = (module Notifier.S)) =
struct
  let send address =
    List.map
      (fun (module Notifier : Notifier.S) -> Notifier.notify address)
      Notifiers.all
end

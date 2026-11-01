[@@deriving workflow] with [@@transitions]: each transition is a function
from states to a state, so a wrong state name does not compile.

  $ cat > input.ml <<'ML'
  > type t = Cart | Paid | Cancelled
  > [@@deriving workflow]
  > [@@transitions { pay = (function Cart -> Paid); cancel = (function Cart | Paid -> Cancelled) }]
  > ML
  $ ./pp.exe -impl input.ml | sed -n '/type transition/,$p'
      type transition =
        | Pay 
        | Cancel 
      let transitions : transition list = [Pay; Cancel]
      let _ = transitions
      let transition_name : transition -> string =
        function | Pay -> "pay" | Cancel -> "cancel"
      let _ = transition_name
      let next : transition -> t -> t option =
        function
        | Pay -> (((function | Cart -> Some Paid | _ -> None))
            [@ocaml.warning "-11"])
        | Cancel -> (((function | Cart | Paid -> Some Cancelled | _ -> None))
            [@ocaml.warning "-11"])
      let _ = next
      let apply transition state =
        Option.to_result ~none:(`Not_allowed (transition, state))
          (next transition state)
      let _ = apply
      let allowed state =
        List.filter_map
          (fun transition ->
             Option.map (fun _ -> transition) (next transition state))
          transitions
      let _ = allowed
      let sources transition =
        List.filter_map
          (fun state -> Option.map (fun _ -> state) (next transition state))
          [Cart; Paid; Cancelled]
      let _ = sources
      let workflow_mermaid =
        "stateDiagram-v2\n  Cart --> Paid: pay\n  Cart --> Cancelled: cancel\n  Paid --> Cancelled: cancel\n"
      let _ = workflow_mermaid
    end[@@ocaml.doc "@inline"][@@merlin.hide ]
  $ cat > input.ml <<'ML'
  > type t = Cart | Paid
  > [@@deriving workflow]
  > [@@transitions { pay = (function Cart -> Payd) }]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 3, characters 41-45:
  3 | [@@transitions { pay = (function Cart -> Payd) }]
                                               ^^^^
  Error: a transition ends in one of the states (Cart, Paid)
  [1]

type t = Cart | Paid | Shipped | Cancelled
[@@deriving dto, workflow]
[@@transitions
  {
    pay = (function Cart -> Paid);
    ship = (function Paid -> Shipped);
    cancel = (function Cart | Paid -> Cancelled);
  }]

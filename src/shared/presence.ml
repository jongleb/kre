(** How many times a query parameter appears, and what the handler holds. *)
type ('a, 'b) t =
  | Required : ('a, 'a) t
  | Optional : ('a, 'a option) t
  | Repeated : ('a, 'a list) t

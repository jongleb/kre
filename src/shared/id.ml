module type S = sig
  include Refined.S with type repr = int

  val first : t
  val succ : t -> t
  val equal : t -> t -> bool
end

module Make () = struct
  type t = int
  type repr = int

  let name = "id"

  let of_repr n =
    if n >= 1 then Ok n
    else Error (Validation.fail ~rule:"min" "must be a positive identifier")

  let to_repr n = n
  let of_json json = Validation.ok_exn (of_repr (Scalar.Int.of_json json))
  let to_json n = Scalar.Int.to_json n
  let t_jsonschema = `Assoc [ ("type", `String "integer"); ("minimum", `Int 1) ]
  let of_string raw = Result.bind (Scalar.Int.of_string raw) of_repr
  let to_string n = string_of_int n
  let pp ppf n = Format.pp_print_int ppf n
  let first = 1
  let succ n = n + 1
  let equal left right = Int.equal left right
end

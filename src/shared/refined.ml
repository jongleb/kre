module type S = sig
  type t
  type repr

  include Scalar.S with type t := t

  val of_repr : repr -> (t, Validation.t) result
  val to_repr : t -> repr
  val pp : Format.formatter -> t -> unit
end

module type RULES = sig
  type base

  val name : string
  val rules : base Validation.rule list
  val constraints : (string * Jsonkit.Jsonschema.t) list
end

module Make (Base : Scalar.S) (C : RULES with type base := Base.t) = struct
  include Base
  include C

  type repr = Base.t

  let of_repr repr = Validation.check C.rules repr
  let to_repr t = t
  let of_json json = Validation.ok_exn (of_repr (Base.of_json json))
  let of_string s = Result.bind (Base.of_string s) of_repr

  let t_jsonschema =
    match Base.t_jsonschema with
    | `Assoc fields ->
        `Assoc ((("title", `String C.name) :: fields) @ C.constraints)
    | base ->
        `Assoc
          (("title", `String C.name)
          :: ("allOf", `List [ base ])
          :: C.constraints)

  let pp ppf t = Format.pp_print_string ppf (Base.to_string t)
end

module String (C : sig
  val name : string
  val min : int
  val max : int
end) =
  Make
    (Scalar.String)
    (struct
      include C

      let rules = [ Validation.min_length C.min; Validation.max_length C.max ]
      let constraints = [ ("minLength", `Int C.min); ("maxLength", `Int C.max) ]
    end)

module Int (C : sig
  val name : string
  val min : int
  val max : int
end) =
  Make
    (Scalar.Int)
    (struct
      include C

      let rules = [ Validation.range ~min:C.min ~max:C.max ]
      let constraints = [ ("minimum", `Int C.min); ("maximum", `Int C.max) ]
    end)

module Pattern (C : sig
  val name : string
  val pattern : string
end) =
  Make
    (Scalar.String)
    (struct
      include C

      let rules = [ Validation.pattern C.pattern ]
      let constraints = [ ("pattern", `String C.pattern) ]
    end)

module Enum (C : sig
  val name : string
  val values : string list
end) =
  Make
    (Scalar.String)
    (struct
      include C

      let rules = [ Validation.one_of C.values ]

      let constraints =
        [ ("enum", `List (List.map (fun v -> `String v) C.values)) ]
    end)

module Email =
  Make
    (Scalar.String)
    (struct
      let name = "email"
      let rules = [ Validation.email ]
      let constraints = [ ("format", `String "email") ]
    end)

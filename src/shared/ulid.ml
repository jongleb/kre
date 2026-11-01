module type S = sig
  include Refined.S with type repr = string

  val equal : t -> t -> bool
end

let alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

module Make () = struct
  include
    Refined.Make
      (Scalar.String)
      (struct
        let name = "ulid"

        let rules =
          [
            Validation.rule ~name:"ulid" (fun text ->
                match
                  ( String.length text,
                    String.for_all (fun c -> String.contains alphabet c) text )
                with
                | 26, true -> Ok text
                | _ -> Error "must be a ULID: 26 characters of 0-9 and A-Z");
          ]

        let constraints = [ ("pattern", `String "^[0-9A-HJKMNP-TV-Z]{26}$") ]
      end)

  let equal left right = String.equal (to_repr left) (to_repr right)
end

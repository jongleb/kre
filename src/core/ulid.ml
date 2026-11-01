let next ?(now = Unix.gettimeofday ()) () =
  let time = Int64.of_float (now *. 1000.) in
  let random = Dream.random 10 ^ "\000" in
  let digit index = Kre_shared.Ulid.alphabet.[index] in
  String.init 10 (fun index ->
      digit
        (Int64.to_int
           (Int64.logand (Int64.shift_right_logical time (5 * (9 - index))) 31L)))
  ^ String.init 16 (fun index ->
      let bit = 5 * index in
      let word =
        (Char.code random.[bit / 8] lsl 8) lor Char.code random.[(bit / 8) + 1]
      in
      digit ((word lsr (11 - (bit mod 8))) land 31))

let length text =
  String.fold_left
    (fun total byte ->
      match Char.code byte land 0xC0 with 0x80 -> total | _ -> total + 1)
    0 text

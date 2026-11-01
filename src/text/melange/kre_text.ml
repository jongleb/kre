external code_points : string -> string array = "from" [@@mel.scope "Array"]

let length text = Array.length (code_points text)

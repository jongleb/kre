type t = { name : string; svg : string }

let checked ~name svg = { name; svg }
let name icon = icon.name
let svg icon = icon.svg

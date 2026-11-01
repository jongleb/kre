module type S = sig
  val hello : string -> string
end

let hello name = "hello " ^ name

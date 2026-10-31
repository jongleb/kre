let return value = Js.Promise.resolve value
let ( let* ) promise next = Js.Promise.then_ next promise

let ( let+ ) promise f =
  Js.Promise.then_ (fun value -> Js.Promise.resolve (f value)) promise

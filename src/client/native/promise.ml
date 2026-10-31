let return value = Lwt.return value
let ( let* ) promise next = Lwt.bind promise next
let ( let+ ) promise f = Lwt.map f promise

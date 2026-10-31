# Injection scopes

Nest: `Scope.DEFAULT | REQUEST | TRANSIENT`. Forge: `DEFAULT` — модуль, `TRANSIENT` — функция, `REQUEST` — значение в `Dream.field`, которое кладёт middleware и читает guard. Сервис, которому нужно значение запроса, получает его аргументом функции, а не конструктора, поэтому «всплытия» скоупа нет.

<!-- $MDX file=examples/request_id.ml -->
```ocaml
let field : int Dream.field = Dream.new_field ~name:"request_id" ()
let next_id = ref 0

let use : Dream.middleware =
 fun next request ->
  incr next_id;
  Dream.set_field request field !next_id;
  next request

let current : int Forge.Guard.t =
  Forge.Guard.field field
    ~missing:(Forge.Error.internal "Request_id.use is not installed")
```

<!-- $MDX file=examples/trace_controller.ml -->
```ocaml
[@@@controller "trace"]
[@@@use [ Request_id.use ]]

let show ~(id : (int[@guard Request_id.current])) () : string Lwt.t =
  Lwt.return (Printf.sprintf "request %d" id)
[@@get]
```


# Injection scopes

Nest: `Scope.DEFAULT | REQUEST | TRANSIENT`. Kre: `DEFAULT` is a module, `TRANSIENT` is a function, `REQUEST` is a value in `Dream.field` that middleware puts there and a guard reads. A service that needs a request value gets it as a function argument, not a constructor argument, so the scope does not "bubble up".

<!-- $MDX file=examples/request_id.ml -->
```ocaml
let field : int Dream.field = Dream.new_field ~name:"request_id" ()
let next_id = ref 0

let use : Dream.middleware =
 fun next request ->
  incr next_id;
  Dream.set_field request field !next_id;
  next request

let current : int Kre.Guard.t =
  Kre.Guard.field field
    ~missing:(Kre.Error.internal "Request_id.use is not installed")
```

<!-- $MDX file=examples/trace_controller.ml -->
```ocaml
[@@@controller "trace"]
[@@@use [ Request_id.use ]]

let show ~(id : (int[@guard Request_id.current])) () : string Lwt.t =
  Lwt.return (Printf.sprintf "request %d" id)
[@@get]
```


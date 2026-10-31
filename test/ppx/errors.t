[@@@controller] must come first.

  $ cat > input.ml <<'ML'
  > let x = 1
  > [@@@controller "cats"]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 2, characters 0-22:
  2 | [@@@controller "cats"]
      ^^^^^^^^^^^^^^^^^^^^^^
  Error: [@@@controller] must be the first item of the file
  [1]

A file is one controller.

  $ cat > input.ml <<'ML'
  > [@@@controller "cats"]
  > [@@@controller "dogs"]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 2, characters 0-22:
  2 | [@@@controller "dogs"]
      ^^^^^^^^^^^^^^^^^^^^^^
  Error: second [@@@controller]; a file is one controller
  [1]

A verb outside a controller.

  $ cat > input.ml <<'ML'
  > let f () : unit Lwt.t = Lwt.return_unit [@@get]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 1, characters 40-47:
  1 | let f () : unit Lwt.t = Lwt.return_unit [@@get]
                                              ^^^^^^^
  Error: [@@get] outside a controller; add [@@@controller "prefix"] as the first item of the file
  [1]

A handler needs a plain name.

  $ cat > input.ml <<'ML'
  > [@@@controller "c"]
  > let (a, b) = (1, 2) [@@get]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 2, characters 4-10:
  2 | let (a, b) = (1, 2) [@@get]
          ^^^^^^
  Error: [@@get] needs a plain name: let find_one … = …
  [1]

Handlers cannot be recursive.

  $ cat > input.ml <<'ML'
  > [@@@controller "c"]
  > let rec f () : unit Lwt.t = f () [@@get]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 2, characters 33-40:
  2 | let rec f () : unit Lwt.t = f () [@@get]
                                       ^^^^^^^
  Error: [@@get] on let rec: handlers cannot be recursive; move the recursion into a helper
  [1]

One handler per let.

  $ cat > input.ml <<'ML'
  > [@@@controller "c"]
  > let f () : unit Lwt.t = Lwt.return_unit [@@get]
  > and g () : unit Lwt.t = Lwt.return_unit
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 2, characters 40-47:
  2 | let f () : unit Lwt.t = Lwt.return_unit [@@get]
                                              ^^^^^^^
  Error: [@@get] on let … and …: declare each handler with its own let
  [1]

Missing return type.

  $ cat > input.ml <<'ML'
  > [@@@controller "c"]
  > let f () = Lwt.return_unit [@@get]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 2, characters 6-26:
  2 | let f () = Lwt.return_unit [@@get]
            ^^^^^^^^^^^^^^^^^^^^
  Error: handler f: missing return type annotation; add one before =, e.g. : Cat.t Lwt.t
  [1]

A handler must be a function.

  $ cat > input.ml <<'ML'
  > [@@@controller "c"]
  > let f : unit Lwt.t = Lwt.return_unit [@@get]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 2, characters 21-36:
  2 | let f : unit Lwt.t = Lwt.return_unit [@@get]
                           ^^^^^^^^^^^^^^^
  Error: handler f must be a function with its parameters on the let: let f (…) () : t Lwt.t = …
  [1]

A handler must return a promise.

  $ cat > input.ml <<'ML'
  > [@@@controller "c"]
  > let f () : int = 1 [@@get]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 2, characters 11-14:
  2 | let f () : int = 1 [@@get]
                 ^^^
  Error: handler f must return a promise: t Lwt.t or (t, Forge.Error.t) result Lwt.t, where t is unit, string, Dream.response, T.t, T.t list or T.t option
  [1]

Unsupported return type.

  $ cat > input.ml <<'ML'
  > [@@@controller "c"]
  > let f () : (int * int) Lwt.t = Lwt.return (1, 2) [@@get]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 2, characters 11-28:
  2 | let f () : (int * int) Lwt.t = Lwt.return (1, 2) [@@get]
                 ^^^^^^^^^^^^^^^^^
  Error: unsupported type (int * int); path and query parameters take int, int64, float, bool, string or T.t with T : Forge_shared.Scalar.S; bodies and results also take T.t with T : Forge_shared.Json.S and lists of those
  [1]

Path segment without a parameter.

  $ cat > input.ml <<'ML'
  > [@@@controller "c"]
  > let f () : unit Lwt.t = Lwt.return_unit [@@get ":id"]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 2, characters 40-53:
  2 | let f () : unit Lwt.t = Lwt.return_unit [@@get ":id"]
                                              ^^^^^^^^^^^^^
  Error: path segment :id has no parameter; add ~(id : int) to the handler
  [1]

Path parameter without a type.

  $ cat > input.ml <<'ML'
  > [@@@controller "c"]
  > let f ~id : unit Lwt.t = ignore id; Lwt.return_unit [@@get ":id"]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 2, characters 6-9:
  2 | let f ~id : unit Lwt.t = ignore id; Lwt.return_unit [@@get ":id"]
            ^^^
  Error: parameter id needs a type annotation: ~(id : int)
  [1]

Optional path parameter.

  $ cat > input.ml <<'ML'
  > [@@@controller "c"]
  > let f ?(id : int option) () : unit Lwt.t = ignore id; Lwt.return_unit [@@get ":id"]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 2, characters 6-24:
  2 | let f ?(id : int option) () : unit Lwt.t = ignore id; Lwt.return_unit [@@get ":id"]
            ^^^^^^^^^^^^^^^^^^
  Error: path parameter id cannot be optional; use ~(id : …)
  [1]

Unsupported path type.

  $ cat > input.ml <<'ML'
  > [@@@controller "c"]
  > let f ~(id : int list) : unit Lwt.t = ignore id; Lwt.return_unit [@@get ":id"]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 2, characters 6-22:
  2 | let f ~(id : int list) : unit Lwt.t = ignore id; Lwt.return_unit [@@get ":id"]
            ^^^^^^^^^^^^^^^^
  Error: unsupported type int list; path and query parameters take int, int64, float, bool, string or T.t with T : Forge_shared.Scalar.S; bodies and results also take T.t with T : Forge_shared.Json.S and lists of those
  [1]

Two bodies.

  $ cat > input.ml <<'ML'
  > [@@@controller "c"]
  > let g ~(body : A.t) ~body:(other : A.t) : unit Lwt.t = ignore (body, other); Lwt.return_unit [@@post]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 2, characters 20-39:
  2 | let g ~(body : A.t) ~body:(other : A.t) : unit Lwt.t = ignore (body, other); Lwt.return_unit [@@post]
                          ^^^^^^^^^^^^^^^^^^^
  Error: handler g has two body parameters; keep one ~(body : T.t)
  [1]

Unsupported body type.

  $ cat > input.ml <<'ML'
  > [@@@controller "c"]
  > let f ~(body : int * int) : unit Lwt.t = ignore body; Lwt.return_unit [@@post]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 2, characters 6-25:
  2 | let f ~(body : int * int) : unit Lwt.t = ignore body; Lwt.return_unit [@@post]
            ^^^^^^^^^^^^^^^^^^^
  Error: unsupported type (int * int); path and query parameters take int, int64, float, bool, string or T.t with T : Forge_shared.Scalar.S; bodies and results also take T.t with T : Forge_shared.Json.S and lists of those
  [1]

Positional parameter that is not a request.

  $ cat > input.ml <<'ML'
  > [@@@controller "c"]
  > let f (x : int) : unit Lwt.t = ignore x; Lwt.return_unit [@@get]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 2, characters 6-15:
  2 | let f (x : int) : unit Lwt.t = ignore x; Lwt.return_unit [@@get]
            ^^^^^^^^^
  Error: positional parameter must be (module M : S), (req : Dream.request), (x : t [@from guard]) or (); use a labelled parameter for path, query and body values
  [1]

Optional query parameter without a default.

  $ cat > input.ml <<'ML'
  > [@@@controller "c"]
  > let f ?(page : int) () : unit Lwt.t = ignore page; Lwt.return_unit [@@get]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 2, characters 6-19:
  2 | let f ?(page : int) () : unit Lwt.t = ignore page; Lwt.return_unit [@@get]
            ^^^^^^^^^^^^^
  Error: optional parameter page needs a default or an option type: ?(page : int = 0) or ?(page : int option)
  [1]

A dependency with two signatures.

  $ cat > input.ml <<'ML'
  > [@@@controller "c"]
  > let f (module Db : A.S) () : unit Lwt.t = Db.x () [@@get]
  > let g (module Db : B.S) () : unit Lwt.t = Db.x () [@@post]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 3, characters 6-23:
  3 | let g (module Db : B.S) () : unit Lwt.t = Db.x () [@@post]
            ^^^^^^^^^^^^^^^^^
  Error: dependency Db has two signatures in this controller, A.S and B.S; rename one of them
  [1]

Status out of range.

  $ cat > input.ml <<'ML'
  > [@@@controller "c"]
  > let f () : unit Lwt.t = Lwt.return_unit [@@get] [@@status 42]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 2, characters 48-61:
  2 | let f () : unit Lwt.t = Lwt.return_unit [@@get] [@@status 42]
                                                      ^^^^^^^^^^^^^
  Error: [@@status 42] is not an HTTP status; use 100–599
  [1]

Middleware must be a list literal.

  $ cat > input.ml <<'ML'
  > [@@@controller "c"]
  > [@@@use Logger.use]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 2, characters 8-18:
  2 | [@@@use Logger.use]
              ^^^^^^^^^^
  Error: [@@use] expects a list literal, e.g. [@@use [ a; b ]]
  [1]

A guard needs an expression.

  $ cat > input.ml <<'ML'
  > [@@@controller "c"]
  > let f ~(user : User.t [@guard]) () : unit Lwt.t = ignore user; Lwt.return_unit [@@get]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 2, characters 22-30:
  2 | let f ~(user : User.t [@guard]) () : unit Lwt.t = ignore user; Lwt.return_unit [@@get]
                            ^^^^^^^^
  Error: [@guard] expects a guard expression of type 'a Forge.Guard.t
  [1]

Redirect needs a unit handler.

  $ cat > input.ml <<'ML'
  > [@@@controller "c"]
  > let f () : string Lwt.t = Lwt.return "x" [@@get] [@@redirect "/x"]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 2, characters 49-66:
  2 | let f () : string Lwt.t = Lwt.return "x" [@@get] [@@redirect "/x"]
                                                       ^^^^^^^^^^^^^^^^^
  Error: [@@redirect] needs a handler returning unit Lwt.t
  [1]

Timeout takes seconds as a float.

  $ cat > input.ml <<'ML'
  > [@@@controller "c"]
  > let f () : unit Lwt.t = Lwt.return_unit [@@get] [@@timeout 5]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 2, characters 48-61:
  2 | let f () : unit Lwt.t = Lwt.return_unit [@@get] [@@timeout 5]
                                                      ^^^^^^^^^^^^^
  Error: [@@timeout] expects seconds as a float: [@@timeout 5.0]
  [1]

[@@transactional] and [@from Db.tx] come together.

  $ cat > input.ml <<'ML'
  > [@@@controller "c"]
  > let f () : unit Lwt.t = Lwt.return_unit [@@post] [@@transactional]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 2, characters 49-66:
  2 | let f () : unit Lwt.t = Lwt.return_unit [@@post] [@@transactional]
                                                       ^^^^^^^^^^^^^^^^^
  Error: [@@transactional] needs the connection: add ~(conn : Db.conn [@from Db.tx]) where Db is a Forge.Db.S dependency
  [1]
  $ cat > input.ml <<'ML'
  > [@@@controller "c"]
  > let f (module Db : Forge.Db.S) ~(conn : Db.conn [@from Db.tx]) () : unit Lwt.t =
  >   ignore conn; Lwt.return_unit
  > [@@post]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 2, characters 31-62:
  2 | let f (module Db : Forge.Db.S) ~(conn : Db.conn [@from Db.tx]) () : unit Lwt.t =
                                     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Error: [@from Db.tx] reads the open transaction; add [@@transactional] to f
  [1]

[@@authorize] takes a literal function over the handler's labels.

  $ cat > input.ml <<'ML'
  > [@@@controller "c"]
  > let f ~(id : int) : unit Lwt.t = ignore id; Lwt.return_unit
  > [@@get ":id"] [@@authorize fun ~id ~owner -> check id owner]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 3, characters 27-59:
  3 | [@@get ":id"] [@@authorize fun ~id ~owner -> check id owner]
                                 ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Error: [@@authorize] uses ~owner, which f does not take
  [1]

A stream needs [@@sse], and [@@sse] needs a stream.

  $ cat > input.ml <<'ML'
  > [@@@controller "c"]
  > let f () : T.t Lwt_stream.t Lwt.t = Lwt.return (Lwt_stream.of_list []) [@@get]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 2, characters 11-33:
  2 | let f () : T.t Lwt_stream.t Lwt.t = Lwt.return (Lwt_stream.of_list []) [@@get]
                 ^^^^^^^^^^^^^^^^^^^^^^
  Error: handler f returns a stream; add [@@sse] to send it as server-sent events
  [1]
  $ cat > input.ml <<'ML'
  > [@@@controller "c"]
  > let f () : T.t Lwt.t = assert false [@@get] [@@sse]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 2, characters 44-51:
  2 | let f () : T.t Lwt.t = assert false [@@get] [@@sse]
                                                  ^^^^^^^
  Error: [@@sse] needs a handler returning T.t Lwt_stream.t Lwt.t
  [1]


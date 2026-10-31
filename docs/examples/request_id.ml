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

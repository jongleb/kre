val return : 'a -> 'a Js.Promise.t
val ( let* ) : 'a Js.Promise.t -> ('a -> 'b Js.Promise.t) -> 'b Js.Promise.t
val ( let+ ) : 'a Js.Promise.t -> ('a -> 'b) -> 'b Js.Promise.t

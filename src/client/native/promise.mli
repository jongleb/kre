val return : 'a -> 'a Lwt.t
val ( let* ) : 'a Lwt.t -> ('a -> 'b Lwt.t) -> 'b Lwt.t
val ( let+ ) : 'a Lwt.t -> ('a -> 'b) -> 'b Lwt.t

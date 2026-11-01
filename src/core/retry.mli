val run : ?backoff:float -> attempts:int -> (unit -> 'a Lwt.t) -> 'a Lwt.t

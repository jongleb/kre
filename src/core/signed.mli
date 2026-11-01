val url : ?now:float -> secret:string -> expires_in:float -> string -> string
val guard : ?now:(unit -> float) -> secret:string -> unit -> unit Guard.t

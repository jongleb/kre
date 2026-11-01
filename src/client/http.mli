val base_url : string ref
val headers : (string * string) list ref

val request :
  ?base:string ->
  Wire.verb ->
  path:string list ->
  ?query:(string * string) list list ->
  ?headers:(string * string) list list ->
  ?body:string ->
  'a Wire.returns ->
  ('a, Error.t) result Js.Promise.t

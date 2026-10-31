(** Which origins may call the API from a browser. *)
type origins = Any | Only of string list

(** Whether browsers send cookies and auth headers cross-origin. *)
type credentials = Include | Omit

val middleware :
  ?origins:origins ->
  ?methods:string list ->
  ?headers:string list ->
  ?credentials:credentials ->
  ?max_age:int ->
  unit ->
  Dream.middleware

type parent
(** Where routes are mounted: the layouts around them, outermost first. *)

type ('p, 's, 'd) route
(** A page: its params ['p], search ['s] and loader data ['d]. *)

(** A route of any type, to list them together. *)
type any = Any : ('p, 's, 'd) route -> any

type t
(** Routes in matching order. *)

val root : ?layout:(children:React.element -> React.element) -> unit -> parent
val nest : parent -> layout:(children:React.element -> React.element) -> parent
val no_data : 'p -> 's -> unit Js.Promise.t

val child :
  ?live:string list ->
  parent ->
  path:'p Path.t ->
  search:'s Forge_shared.Search.t ->
  loader:('p -> 's -> 'd Js.Promise.t) ->
  component:(data:'d -> params:'p -> search:'s -> React.element) ->
  ('p, 's, 'd) route

val make : any list -> t
val href : ('p, 's, _) route -> params:'p -> search:'s -> string
val navigate : ('p, 's, _) route -> params:'p -> search:'s -> unit

val link :
  ('p, 's, _) route ->
  params:'p ->
  search:'s ->
  children:React.element ->
  React.element

(** Renders the route matching the current URL once its loader resolves. *)
module View : sig
  val make :
    router:t ->
    ?server_url:string ->
    ?pending:React.element ->
    ?not_found:React.element ->
    unit ->
    React.element
  [@@react.component]
end

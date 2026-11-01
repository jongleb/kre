type sql_type =
  | Integer  (** BIGINT *)
  | Text of int option  (** VARCHAR(n), or TEXT without a size. *)
  | Boolean
  | Double

(** How a column takes part in keys. *)
type role = Primary_auto | Primary | Unique | Index | Plain

type nullability = Null | Not_null

(** Columns that [for_insert] and [for_update] fill themselves. *)
type managed =
  | Created_at  (** Set on insert, never updated. *)
  | Updated_at  (** Set on insert and on every update. *)
  | Version
      (** Starts at 0; an update needs the version it read and bumps it. *)

(** How a column filters the [filter] query: equal, contained, or between. *)
type filter = Exact | Partial | Range

type column = private {
  name : string;
  type_ : sql_type;
  nullability : nullability;
  role : role;
  default : string option;  (** SQL expression. *)
  references : string option;  (** Referenced table; its [id] column. *)
  managed : managed option;
  filter : filter option;
}

type t = private {
  name : string;
  columns : column list;
  scopes : (string * string) list;  (** Named SQL conditions. *)
  prune : string option;  (** The time column [prune] deletes by. *)
}
(** A table, described by [[@@deriving table]] from an OCaml record. *)

(** Whose DDL [ddl] and [schema] print; CRUD queries are the same for both. *)
type dialect = Mysql | Postgresql

val column :
  ?role:role ->
  ?managed:managed ->
  ?filter:filter ->
  ?default:string ->
  ?references:t ->
  string ->
  sql_type ->
  nullability ->
  column

val make :
  ?scopes:(string * string) list ->
  ?prune:string ->
  name:string ->
  column list ->
  t

val group : key:('a -> 'k) -> 'a list -> 'k -> 'a list
val ddl : dialect -> t -> string
val schema : dialect -> t list -> string
val crud : t -> string
val now : unit -> Kre_shared.Time.t
val decode : (module S : Kre_shared.Scalar.S) -> string -> S.t

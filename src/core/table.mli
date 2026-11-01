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

type column = private {
  name : string;
  type_ : sql_type;
  nullability : nullability;
  role : role;
  default : string option;  (** SQL expression. *)
  references : string option;  (** Referenced table; its [id] column. *)
  managed : managed option;
}

type t = private { name : string; columns : column list }
(** A table, described by [[@@deriving table]] from an OCaml record. *)

(** Whose DDL [ddl] and [schema] print; CRUD queries are the same for both. *)
type dialect = Mysql | Postgresql

val column :
  ?role:role ->
  ?managed:managed ->
  ?default:string ->
  ?references:t ->
  string ->
  sql_type ->
  nullability ->
  column

val make : name:string -> column list -> t
val ddl : dialect -> t -> string
val schema : dialect -> t list -> string
val crud : t -> string
val now : unit -> Forge_shared.Time.t
val decode : (module S : Forge_shared.Scalar.S) -> string -> S.t

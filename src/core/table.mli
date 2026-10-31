type sql_type =
  | Integer  (** BIGINT *)
  | Text of int option  (** VARCHAR(n), or TEXT without a size. *)
  | Boolean
  | Double

(** How a column takes part in keys. *)
type role = Primary_auto | Primary | Unique | Index | Plain

type nullability = Null | Not_null

type column = private {
  name : string;
  type_ : sql_type;
  nullability : nullability;
  role : role;
  default : string option;  (** SQL expression. *)
  references : string option;  (** Referenced table; its [id] column. *)
}

type t = private { name : string; columns : column list }
(** A table, described by [[@@deriving table]] from an OCaml record. *)

(** Whose DDL [ddl] and [schema] print; CRUD queries are the same for both. *)
type dialect = Mysql | Postgresql

val column :
  ?role:role ->
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
val decode : (module S : Forge_shared.Scalar.S) -> string -> S.t

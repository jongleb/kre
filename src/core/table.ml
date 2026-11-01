type sql_type = Integer | Text of int option | Boolean | Double
type role = Primary_auto | Primary | Unique | Index | Plain
type nullability = Null | Not_null
type managed = Created_at | Updated_at | Version
type filter = Exact | Partial | Range

type column = {
  name : string;
  type_ : sql_type;
  nullability : nullability;
  role : role;
  default : string option;
  references : string option;
  managed : managed option;
  filter : filter option;
}

type t = {
  name : string;
  columns : column list;
  scopes : (string * string) list;
  prune : string option;
}

type dialect = Mysql | Postgresql

let column ?(role = Plain) ?managed ?filter ?default ?references name type_
    nullability =
  {
    managed;
    filter;
    name;
    type_;
    nullability;
    role;
    default;
    references = Option.map (fun (table : t) -> table.name) references;
  }

let make ?(scopes = []) ?prune ~name columns = { name; columns; scopes; prune }

let group ~key items =
  let groups = Hashtbl.create 16 in
  List.iter
    (fun item ->
      Hashtbl.replace groups (key item)
        (item :: Option.value ~default:[] (Hashtbl.find_opt groups (key item))))
    (List.rev items);
  fun parent -> Option.value ~default:[] (Hashtbl.find_opt groups parent)

let ddl dialect table =
  let definition (column : column) =
    String.concat " "
      (List.concat
         [
           (match (column.type_, column.role, dialect) with
           | Integer, Primary_auto, Postgresql -> [ column.name; "SERIAL" ]
           | type_, _, _ ->
               [
                 column.name;
                 (match (type_, dialect) with
                 | Integer, _ -> "BIGINT"
                 | Text (Some size), _ -> Printf.sprintf "VARCHAR(%d)" size
                 | Text None, _ -> "TEXT"
                 | Boolean, _ -> "BOOLEAN"
                 | Double, Mysql -> "DOUBLE"
                 | Double, Postgresql -> "DOUBLE PRECISION");
                 (match column.nullability with
                 | Null -> "NULL"
                 | Not_null -> "NOT NULL");
               ]);
           Option.fold ~none:[]
             ~some:(fun default -> [ "DEFAULT"; default ])
             column.default;
           (match (column.role, dialect) with
           | Primary_auto, Mysql -> [ "AUTO_INCREMENT"; "PRIMARY KEY" ]
           | Primary_auto, Postgresql -> [ "PRIMARY KEY" ]
           | Primary, _ -> [ "PRIMARY KEY" ]
           | Unique, _ -> [ "UNIQUE" ]
           | (Index | Plain), _ -> []);
         ])
  in
  let constraints =
    List.concat_map
      (fun (column : column) ->
        (match (column.role, dialect) with
          | Index, Mysql -> [ Printf.sprintf "INDEX (%s)" column.name ]
          | Index, Postgresql
          | (Primary_auto | Primary | Unique | Plain), (Mysql | Postgresql) ->
              [])
        @ Option.fold ~none:[]
            ~some:(fun table ->
              [
                Printf.sprintf "FOREIGN KEY (%s) REFERENCES %s (id)" column.name
                  table;
              ])
            column.references)
      table.columns
  in
  let indexes =
    List.filter_map
      (fun (column : column) ->
        match (column.role, dialect) with
        | Index, Postgresql ->
            Some
              (Printf.sprintf "CREATE INDEX %s_%s ON %s (%s);\n" table.name
                 column.name table.name column.name)
        | Index, Mysql
        | (Primary_auto | Primary | Unique | Plain), (Mysql | Postgresql) ->
            None)
      table.columns
  in
  String.concat ""
    (Printf.sprintf "CREATE TABLE %s (\n  %s\n);\n" table.name
       (String.concat ",\n  " (List.map definition table.columns @ constraints))
    :: indexes)

let schema dialect tables = String.concat "\n" (List.map (ddl dialect) tables)

let crud table =
  let names columns = List.map (fun (column : column) -> column.name) columns in
  let key =
    List.find_opt
      (fun (column : column) ->
        match column.role with
        | Primary_auto | Primary -> true
        | Unique | Index | Plain -> false)
      table.columns
  in
  let inserted =
    List.filter
      (fun (column : column) ->
        match column.role with
        | Primary_auto -> false
        | Primary | Unique | Index | Plain -> true)
      table.columns
  in
  let all = String.concat ", " (names table.columns) in
  let order =
    Option.fold
      ~none:
        (Option.fold ~none:"1"
           ~some:(fun (column : column) -> column.name)
           (List.nth_opt table.columns 0))
      ~some:(fun (key : column) -> key.name)
      key
  in
  String.concat "\n"
    ([
       "-- @all";
       Printf.sprintf "SELECT %s FROM %s;" all table.name;
       "-- @insert";
       Printf.sprintf "INSERT INTO %s (%s) VALUES (%s);" table.name
         (String.concat ", " (names inserted))
         (String.concat ", "
            (List.map (fun name -> "@" ^ name) (names inserted)));
     ]
    @ Option.fold ~none:[]
        ~some:(fun (key : column) ->
          let others =
            List.filter
              (fun (column : column) -> not (String.equal column.name key.name))
              table.columns
          in
          [
            "-- @find";
            Printf.sprintf "SELECT %s FROM %s WHERE %s = @%s;" all table.name
              key.name key.name;
            "-- @update";
            Printf.sprintf "UPDATE %s SET %s WHERE %s = @%s%s;" table.name
              (String.concat ", "
                 (List.filter_map
                    (fun (column : column) ->
                      match column.managed with
                      | Some Created_at -> None
                      | Some Version ->
                          Some
                            (Printf.sprintf "%s = %s + 1" column.name
                               column.name)
                      | Some Updated_at | None ->
                          Some (column.name ^ " = @" ^ column.name))
                    others))
              key.name key.name
              (String.concat ""
                 (List.filter_map
                    (fun (column : column) ->
                      match column.managed with
                      | Some Version ->
                          Some
                            (Printf.sprintf " AND %s = @%s" column.name
                               column.name)
                      | Some (Created_at | Updated_at) | None -> None)
                    others));
            "-- @delete";
            Printf.sprintf "DELETE FROM %s WHERE %s = @%s;" table.name key.name
              key.name;
            "-- @page";
            Printf.sprintf
              "SELECT %s FROM %s ORDER BY %s LIMIT @limit OFFSET @offset;" all
              table.name key.name;
          ])
        key
    @ List.concat_map
        (fun (column : column) ->
          match (column.role, column.references) with
          | Unique, _ ->
              [
                "-- @by_" ^ column.name;
                Printf.sprintf "SELECT %s FROM %s WHERE %s = @%s;" all
                  table.name column.name column.name;
              ]
          | Index, _ | Plain, Some _ ->
              [
                "-- @by_" ^ column.name;
                Printf.sprintf "SELECT %s FROM %s WHERE %s = @%s%s;" all
                  table.name column.name column.name
                  (Option.fold ~none:""
                     ~some:(fun (key : column) -> " ORDER BY " ^ key.name)
                     key);
              ]
          | (Primary_auto | Primary), _ | Plain, None -> [])
        table.columns
    @ List.concat_map
        (fun (column : column) ->
          match (column.references, column.role) with
          | Some _, (Plain | Index | Unique) ->
              [
                Printf.sprintf "-- @by_%s_any" column.name;
                Printf.sprintf
                  "SELECT %s FROM %s WHERE %s IN @%s_list ORDER BY %s;" all
                  table.name column.name column.name order;
              ]
          | Some _, (Primary_auto | Primary) | None, _ -> [])
        table.columns
    @ List.concat_map
        (fun (scope, condition) ->
          [
            "-- @all_" ^ scope;
            Printf.sprintf "SELECT %s FROM %s WHERE %s ORDER BY %s;" all
              table.name condition order;
            "-- @page_" ^ scope;
            Printf.sprintf
              "SELECT %s FROM %s WHERE %s ORDER BY %s LIMIT @limit OFFSET \
               @offset;"
              all table.name condition order;
            "-- @count_" ^ scope;
            Printf.sprintf "SELECT COUNT(*) FROM %s WHERE %s;" table.name
              condition;
          ])
        table.scopes
    @ (match
         List.concat_map
           (fun (column : column) ->
             match column.filter with
             | None -> []
             | Some Exact ->
                 [ Printf.sprintf "{ %s = @%s }?" column.name column.name ]
             | Some Partial ->
                 [
                   Printf.sprintf "{ %s LIKE CONCAT('%%', @%s, '%%') }?"
                     column.name column.name;
                 ]
             | Some Range ->
                 [
                   Printf.sprintf "{ %s >= @%s_min }?" column.name column.name;
                   Printf.sprintf "{ %s <= @%s_max }?" column.name column.name;
                 ])
           table.columns
       with
      | [] -> []
      | conditions ->
          let where = String.concat " AND " conditions in
          [
            "-- @filter";
            Printf.sprintf
              "SELECT %s FROM %s WHERE %s ORDER BY %s LIMIT @limit OFFSET \
               @offset;"
              all table.name where order;
            "-- @filter_count";
            Printf.sprintf "SELECT COUNT(*) FROM %s WHERE %s;" table.name where;
          ])
    @ Option.fold ~none:[]
        ~some:(fun column ->
          [
            "-- @prune";
            Printf.sprintf "DELETE FROM %s WHERE %s < @before;" table.name
              column;
          ])
        table.prune
    @ [ "-- @count"; Printf.sprintf "SELECT COUNT(*) FROM %s;" table.name; "" ]
    )

let now () = Kre_shared.Time.of_seconds (Unix.gettimeofday ())

let decode (module S : Kre_shared.Scalar.S) raw =
  Kre_shared.Validation.ok_exn (S.of_string raw)

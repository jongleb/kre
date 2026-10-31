type sql_type = Integer | Text of int option | Boolean | Double
type role = Primary_auto | Primary | Unique | Index | Plain
type nullability = Null | Not_null

type column = {
  name : string;
  type_ : sql_type;
  nullability : nullability;
  role : role;
  default : string option;
  references : string option;
}

type t = { name : string; columns : column list }

let column ?(role = Plain) ?default ?references name type_ nullability =
  {
    name;
    type_;
    nullability;
    role;
    default;
    references = Option.map (fun (table : t) -> table.name) references;
  }

let make ~name columns = { name; columns }

let ddl table =
  let definition (column : column) =
    String.concat " "
      (List.concat
         [
           [
             column.name;
             (match column.type_ with
             | Integer -> "BIGINT"
             | Text (Some size) -> Printf.sprintf "VARCHAR(%d)" size
             | Text None -> "TEXT"
             | Boolean -> "BOOLEAN"
             | Double -> "DOUBLE");
             (match column.nullability with
             | Null -> "NULL"
             | Not_null -> "NOT NULL");
           ];
           Option.fold ~none:[]
             ~some:(fun default -> [ "DEFAULT"; default ])
             column.default;
           (match column.role with
           | Primary_auto -> [ "AUTO_INCREMENT"; "PRIMARY KEY" ]
           | Primary -> [ "PRIMARY KEY" ]
           | Unique -> [ "UNIQUE" ]
           | Index | Plain -> []);
         ])
  in
  let constraints =
    List.concat_map
      (fun (column : column) ->
        match (column.role, column.references) with
        | Index, None -> [ Printf.sprintf "INDEX (%s)" column.name ]
        | Index, Some table ->
            [
              Printf.sprintf "INDEX (%s)" column.name;
              Printf.sprintf "FOREIGN KEY (%s) REFERENCES %s (id)" column.name
                table;
            ]
        | (Primary_auto | Primary | Unique | Plain), Some table ->
            [
              Printf.sprintf "FOREIGN KEY (%s) REFERENCES %s (id)" column.name
                table;
            ]
        | (Primary_auto | Primary | Unique | Plain), None -> [])
      table.columns
  in
  Printf.sprintf "CREATE TABLE %s (\n  %s\n);\n" table.name
    (String.concat ",\n  " (List.map definition table.columns @ constraints))

let schema tables = String.concat "\n" (List.map ddl tables)

let decode (module S : Forge_shared.Scalar.S) raw =
  Forge_shared.Validation.ok_exn (S.of_string raw)

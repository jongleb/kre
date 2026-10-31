[@@deriving table] describes the table for DDL and gives an of_row in the
shape of a sqlgg callback.

  $ cat > input.ml <<'ML'
  > type t = {
  >   id : int; [@primary] [@auto]
  >   email : Email.t; [@column string] [@size 255] [@unique]
  >   age : int option;
  >   owner_id : int option; [@references User] [@index]
  >   created : float; [@sql.default "0"]
  > }
  > [@@deriving table ~name:"people"]
  > ML
  $ ./pp.exe -impl input.ml | sed -n '/let table/,$p'
      let table : Forge.Table.t =
        Forge.Table.make ~name:"people"
          [Forge.Table.column ~role:Forge.Table.Primary_auto "id"
             Forge.Table.Integer Forge.Table.Not_null;
          Forge.Table.column ~role:Forge.Table.Unique "email"
            (Forge.Table.Text (Some 255)) Forge.Table.Not_null;
          Forge.Table.column "age" Forge.Table.Integer Forge.Table.Null;
          Forge.Table.column ~role:Forge.Table.Index ~references:User.table
            "owner_id" Forge.Table.Integer Forge.Table.Null;
          Forge.Table.column ~default:"0" "created" Forge.Table.Double
            Forge.Table.Not_null]
      let _ = table
      let of_row ~id:(id : int64) ~email:(email : string)
        ~age:(age : int64 option) ~owner_id:(owner_id : int64 option)
        ~created:(created : float) =
        ({
           id = (Int64.to_int id);
           email = (Forge.Table.decode (module Email) email);
           age = (Option.map (fun value -> Int64.to_int value) age);
           owner_id = (Option.map (fun value -> Int64.to_int value) owner_id);
           created
         } : t)
      let _ = of_row
    end[@@ocaml.doc "@inline"][@@merlin.hide ]

Under -melange it emits nothing.

  $ ./pp.exe -melange -impl input.ml | sed -n '/let table/,$p'

An abstract field needs its column type.

  $ cat > input.ml <<'ML'
  > type t = { email : Email.t } [@@deriving table ~name:"people"]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 1, characters 19-26:
  1 | type t = { email : Email.t } [@@deriving table ~name:"people"]
                         ^^^^^^^
  Error: field email has abstract type Email.t; name its column type: [@column int], [@column string], [@column bool] or [@column float]
  [1]

One key role per field; auto needs primary.

  $ cat > input.ml <<'ML'
  > type t = { id : int [@primary] [@unique] } [@@deriving table ~name:"people"]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 1, characters 11-40:
  1 | type t = { id : int [@primary] [@unique] } [@@deriving table ~name:"people"]
                 ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Error: field id has several key roles (primary, unique); keep one of [@primary], [@unique], [@index]
  [1]
  $ cat > input.ml <<'ML'
  > type t = { id : int [@auto] } [@@deriving table ~name:"people"]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 1, characters 11-27:
  1 | type t = { id : int [@auto] } [@@deriving table ~name:"people"]
                 ^^^^^^^^^^^^^^^^
  Error: [@auto] needs [@primary]: only an integer primary key increments
  [1]

The table needs a name.

  $ cat > input.ml <<'ML'
  > type t = { id : int } [@@deriving table]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 1, characters 0-40:
  1 | type t = { id : int } [@@deriving table]
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Error: [@@deriving table] needs the table name: [@@deriving table ~name:"cats"]
  [1]

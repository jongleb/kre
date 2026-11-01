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
      let table : Kre.Table.t =
        Kre.Table.make ~name:"people"
          [Kre.Table.column ~role:Kre.Table.Primary_auto "id" Kre.Table.Integer
             Kre.Table.Not_null;
          Kre.Table.column ~role:Kre.Table.Unique "email"
            (Kre.Table.Text (Some 255)) Kre.Table.Not_null;
          Kre.Table.column "age" Kre.Table.Integer Kre.Table.Null;
          Kre.Table.column ~role:Kre.Table.Index ~references:User.table
            "owner_id" Kre.Table.Integer Kre.Table.Null;
          Kre.Table.column ~default:"0" "created" Kre.Table.Double
            Kre.Table.Not_null]
      let _ = table
      let for_insert (__kre_record : t) __kre_query =
        let __kre_now = Kre.Table.now () in
        __kre_query ~email:(Email.to_string __kre_record.email)
          ~age:(Option.map (fun value -> Int64.of_int value) __kre_record.age)
          ~owner_id:(Option.map (fun value -> Int64.of_int value)
                       __kre_record.owner_id) ~created:(__kre_record.created)
      let _ = for_insert
      let for_update (__kre_record : t) __kre_query =
        let __kre_now = Kre.Table.now () in
        __kre_query ~email:(Email.to_string __kre_record.email)
          ~age:(Option.map (fun value -> Int64.of_int value) __kre_record.age)
          ~owner_id:(Option.map (fun value -> Int64.of_int value)
                       __kre_record.owner_id) ~created:(__kre_record.created)
          ~id:(Int64.of_int __kre_record.id)
      let _ = for_update
      let of_row ~id:(id : int64) ~email:(email : string)
        ~age:(age : int64 option) ~owner_id:(owner_id : int64 option)
        ~created:(created : float) =
        ({
           id = (Int64.to_int id);
           email = (Kre.Table.decode (module Email) email);
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

[@created_at], [@updated_at] and [@version] are filled by for_insert and
for_update; the update needs the version it read.

  $ cat > input.ml <<'ML'
  > type t = {
  >   id : int; [@primary] [@auto]
  >   name : string;
  >   created_at : Kre_shared.Time.t; [@created_at]
  >   updated_at : Kre_shared.Time.t; [@updated_at]
  >   version : int; [@version]
  > }
  > [@@deriving table ~name:"notes"]
  > ML
  $ ./pp.exe -impl input.ml | sed -n '/let for_insert/,/let _ = for_update/p'
      let for_insert (__kre_record : t) __kre_query =
        let __kre_now = Kre.Table.now () in
        __kre_query ~name:(__kre_record.name)
          ~created_at:(Kre_shared.Time.to_seconds __kre_now)
          ~updated_at:(Kre_shared.Time.to_seconds __kre_now) ~version:0L
      let _ = for_insert
      let for_update (__kre_record : t) __kre_query =
        let __kre_now = Kre.Table.now () in
        __kre_query ~name:(__kre_record.name)
          ~updated_at:(Kre_shared.Time.to_seconds __kre_now)
          ~id:(Int64.of_int __kre_record.id)
          ~version:(Int64.of_int __kre_record.version)
      let _ = for_update
  $ cat > input.ml <<'ML'
  > type t = { id : int; [@primary] at : float [@created_at] }
  > [@@deriving table ~name:"notes"]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 1, characters 43-56:
  1 | type t = { id : int; [@primary] at : float [@created_at] }
                                                 ^^^^^^^^^^^^^
  Error: [@created_at] fills a timestamp; give at the type Kre_shared.Time.t
  [1]

[@slug_from name] fills a field from another one on insert and update.

  $ cat > input.ml <<'ML'
  > type t = {
  >   id : int; [@primary] [@auto]
  >   title : string;
  >   slug : string; [@slug_from title] [@unique]
  > }
  > [@@deriving table ~name:"posts"]
  > ML
  $ ./pp.exe -impl input.ml | sed -n '/let for_insert/,/let _ = for_update/p'
      let for_insert (__kre_record : t) __kre_query =
        let __kre_now = Kre.Table.now () in
        __kre_query ~title:(__kre_record.title)
          ~slug:(Kre_shared.Slug.of_string __kre_record.title)
      let _ = for_insert
      let for_update (__kre_record : t) __kre_query =
        let __kre_now = Kre.Table.now () in
        __kre_query ~title:(__kre_record.title)
          ~slug:(Kre_shared.Slug.of_string __kre_record.title)
          ~id:(Int64.of_int __kre_record.id)
      let _ = for_update
  $ cat > input.ml <<'ML'
  > type t = { id : int; [@primary] slug : string [@slug_from headline] }
  > [@@deriving table ~name:"posts"]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 1, characters 46-67:
  1 | type t = { id : int; [@primary] slug : string [@slug_from headline] }
                                                    ^^^^^^^^^^^^^^^^^^^^^
  Error: [@slug_from headline]: the record has no field headline
  [1]

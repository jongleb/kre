[@@deriving dto] becomes jsonkit's json and jsonschema derivers; fields with
[@validate] get an of_json that checks them all and reports their JSON paths.

  $ cat > input.ml <<'ML'
  > type t = {
  >   name : string; [@key "fullName"] [@validate min_length 1; max_length 8]
  >   tag : string; [@validate.custom fun s -> if s = "x" then Error "no x" else Ok s]
  >   age : int;
  > }
  > [@@deriving dto ~strict]
  > ML
  $ ./pp.exe -impl input.ml | sed -n '1,7p;/^let of_json __kre_json/,$p'
  type t =
    {
    name: string [@key "fullName"][@validate min_length 1; max_length 8];
    tag: string
      [@validate.custom fun s -> if s = "x" then Error "no x" else Ok s];
    age: int }[@@deriving (json, jsonschema)][@@disallow_extra_fields ]
  include
  let of_json __kre_json =
    let __kre_value = of_json __kre_json in
    Kre_shared.Validation.ok_exn
      (let open Kre_shared.Validation.Syntax in
         let+ __kre_name =
           Kre_shared.Validation.field "fullName"
             [(let open Kre_shared.Validation in min_length 1);
             (let open Kre_shared.Validation in max_length 8)] __kre_value.name
         and+ __kre_tag =
           Kre_shared.Validation.field "tag"
             [Kre_shared.Validation.rule ~name:"custom"
                (fun s -> if s = "x" then Error "no x" else Ok s)]
             __kre_value.tag in
         { __kre_value with name = __kre_name; tag = __kre_tag })

Every field checked: no record update.

  $ cat > input.ml <<'ML'
  > type pet = { name : string [@validate max_length 8] } [@@deriving dto]
  > ML
  $ ./pp.exe -impl input.ml | sed -n '/^let pet_of_json __kre_json/,$p'
  let pet_of_json __kre_json =
    let __kre_value = pet_of_json __kre_json in
    Kre_shared.Validation.ok_exn
      (let open Kre_shared.Validation.Syntax in
         let+ __kre_name =
           Kre_shared.Validation.field "name"
             [(let open Kre_shared.Validation in max_length 8)]
             __kre_value.name
          in { name = __kre_name })

Options other than ~strict are for phase 2.

  $ cat > input.ml <<'ML'
  > type t = { a : int } [@@deriving dto ~partial_of:B]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 1, characters 49-50:
  1 | type t = { a : int } [@@deriving dto ~partial_of:B]
                                                       ^
  Error: expected a record type of this file, e.g. ~partial_of:t
  [1]

A rule needs an expression.

  $ cat > input.ml <<'ML'
  > type t = { a : string [@validate] } [@@deriving dto]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 1, characters 22-33:
  1 | type t = { a : string [@validate] } [@@deriving dto]
                            ^^^^^^^^^^^
  Error: [@validate] expects an expression, e.g. [@validate max_length 16]
  [1]

A variant of constant constructors is a scalar: a JSON string, a path or query
segment and a [@column string] in a table. [@key] renames a case.

  $ cat > input.ml <<'ML'
  > type t = Available | Adopted | On_hold [@key "on hold"] [@@deriving dto]
  > ML
  $ ./pp.exe -impl input.ml
  type t =
    | Available 
    | Adopted 
    | On_hold [@key "on hold"]
  let name = "t"
  let to_string =
    function
    | Available -> "available"
    | Adopted -> "adopted"
    | On_hold -> "on hold"
  let of_string =
    function
    | "available" -> Ok Available
    | "adopted" -> Ok Adopted
    | "on hold" -> Ok On_hold
    | _ ->
        Error
          (Kre_shared.Validation.fail ~rule:"one_of"
             "must be one of available, adopted, on hold")
  let to_json __kre_value =
    Jsonkit.declassify (`String (to_string __kre_value))
  let of_json __kre_json =
    match Jsonkit.classify __kre_json with
    | `String __kre_string ->
        Kre_shared.Validation.ok_exn (of_string __kre_string)
    | _ ->
        raise
          (Kre_shared.Validation.Invalid
             (Kre_shared.Validation.fail ~rule:"type" "must be a string"))
  let t_jsonschema =
    `Assoc
      [("type", (`String "string"));
      ("enum",
        (`List [`String "available"; `String "adopted"; `String "on hold"]))]

[@groups] hides a field from the default view; each group gets its own
serializer and schema. Grouped fields become [@option].

  $ cat > member.ml <<'ML'
  > type t = {
  >   id : int;
  >   email : string option; [@groups [ "owner"; "admin" ]]
  >   notes : string option; [@groups [ "admin" ]]
  > }
  > [@@deriving dto]
  > ML
  $ ./pp.exe -impl member.ml | sed -n '/^type t/,/deriving/p; /merlin.hide/,$p'
  type t =
    {
    id: int ;
    email: string option [@option ][@groups ["owner"; "admin"]];
    notes: string option [@option ][@groups ["admin"]]}[@@deriving
    end[@@ocaml.doc "@inline"][@@merlin.hide ]
  let to_json_owner (__kre_value : t) =
    Kre_shared.Json.omit ["notes"] (to_json __kre_value)
  let t_jsonschema_owner = Kre_shared.Json.write_only ["notes"] t_jsonschema
  let to_json_admin (__kre_value : t) =
    Kre_shared.Json.omit [] (to_json __kre_value)
  let t_jsonschema_admin = Kre_shared.Json.write_only [] t_jsonschema
  let to_json (__kre_value : t) =
    Kre_shared.Json.omit ["email"; "notes"] (to_json __kre_value)
  let t_jsonschema = Kre_shared.Json.write_only ["email"; "notes"] t_jsonschema

A grouped field must be an option: other views leave it out.

  $ cat > member.ml <<'ML'
  > type t = { id : int; notes : string [@groups [ "admin" ]] } [@@deriving dto]
  > ML
  $ ./pp.exe -impl member.ml
  File "member.ml", line 1, characters 21-57:
  1 | type t = { id : int; notes : string [@groups [ "admin" ]] } [@@deriving dto]
                           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Error: notes is left out of the views outside its groups, so readers may not get it: make it notes : string option
  [1]

[@view] goes on a DTO type.

  $ cat > members_controller.ml <<'ML'
  > [@@@controller "members"]
  > let count () : (int[@view "admin"]) Lwt.t = Lwt.return 1 [@@get]
  > ML
  $ ./pp.exe -impl members_controller.ml
  File "members_controller.ml", line 2, characters 19-34:
  2 | let count () : (int[@view "admin"]) Lwt.t = Lwt.return 1 [@@get]
                         ^^^^^^^^^^^^^^^
  Error: [@view] goes on a DTO type T.t: (Member.t [@view "admin"])
  [1]

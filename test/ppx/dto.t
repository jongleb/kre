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
  $ ./pp.exe -impl input.ml | sed -n '1,7p;/^let of_json __forge_json/,$p'
  type t =
    {
    name: string [@key "fullName"][@validate min_length 1; max_length 8];
    tag: string
      [@validate.custom fun s -> if s = "x" then Error "no x" else Ok s];
    age: int }[@@deriving (json, jsonschema)][@@disallow_extra_fields ]
  include
  let of_json __forge_json =
    let __forge_value = of_json __forge_json in
    Forge_shared.Validation.ok_exn
      (let open Forge_shared.Validation.Syntax in
         let+ __forge_name =
           Forge_shared.Validation.field "fullName"
             [(let open Forge_shared.Validation in min_length 1);
             (let open Forge_shared.Validation in max_length 8)]
             __forge_value.name
         and+ __forge_tag =
           Forge_shared.Validation.field "tag"
             [Forge_shared.Validation.rule ~name:"custom"
                (fun s -> if s = "x" then Error "no x" else Ok s)]
             __forge_value.tag in
         { __forge_value with name = __forge_name; tag = __forge_tag })

Every field checked: no record update.

  $ cat > input.ml <<'ML'
  > type pet = { name : string [@validate max_length 8] } [@@deriving dto]
  > ML
  $ ./pp.exe -impl input.ml | sed -n '/^let pet_of_json __forge_json/,$p'
  let pet_of_json __forge_json =
    let __forge_value = pet_of_json __forge_json in
    Forge_shared.Validation.ok_exn
      (let open Forge_shared.Validation.Syntax in
         let+ __forge_name =
           Forge_shared.Validation.field "name"
             [(let open Forge_shared.Validation in max_length 8)]
             __forge_value.name
          in { name = __forge_name })

Options other than ~strict are for phase 2.

  $ cat > input.ml <<'ML'
  > type t = { a : int } [@@deriving dto ~partial_of:B]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 1, characters 49-50:
  1 | type t = { a : int } [@@deriving dto ~partial_of:B]
                                                       ^
  Error: [@@deriving dto] takes only ~strict; ~partial_of, ~pick_of and ~omit_of come in phase 2
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

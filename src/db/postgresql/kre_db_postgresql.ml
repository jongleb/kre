module Sql = struct
  module IO = struct
    type 'a future = 'a Lwt.t

    let return value = Lwt.return value
    let ( >>= ) promise next = Lwt.bind promise next

    let bracket resource release use =
      Lwt.bind resource (fun resource ->
          Lwt.finalize (fun () -> use resource) (fun () -> release resource))
  end

  type statement = { conn : Postgresql.connection; sql : string }
  type -'a connection = Postgresql.connection
  type params = { statement : statement; values : string array; next : int ref }
  type row = { result : Postgresql.result; index : int }
  type result = Postgresql.result
  type execute_response = { affected_rows : int64; insert_id : int64 option }

  exception Oops of string

  let blocking run =
    Lwt.bind
      (Lwt_preemptive.detach
         (fun () ->
           match run () with
           | value -> Ok value
           | exception Postgresql.Error error ->
               Error (Postgresql.string_of_error error))
         ())
      (function
        | Ok value -> Lwt.return value
        | Error message -> Lwt.fail (Oops message))

  let run (conn : Postgresql.connection) ?(params = [||]) sql =
    blocking (fun () ->
        conn#exec
          ~expect:[ Postgresql.Command_ok; Postgresql.Tuples_ok ]
          ~params sql)

  let quote text =
    "'" ^ String.concat "''" (String.split_on_char '\'' text) ^ "'"

  module Types = struct
    module Bool = struct
      type t = bool

      let of_text = function
        | "t" | "true" | "1" -> true
        | "f" | "false" | "0" -> false
        | text -> raise (Oops ("not a boolean: " ^ text))

      let to_text = function true -> "t" | false -> "f"
      let to_literal = function true -> "TRUE" | false -> "FALSE"
      let bool_to_literal value = to_literal value
    end

    module Int = struct
      type t = int64

      let of_text text = Int64.of_string text
      let to_text value = Int64.to_string value
      let to_literal value = Int64.to_string value
      let int64_to_literal value = to_literal value
    end

    module UInt64 = struct
      type t = Unsigned.UInt64.t

      let of_text text = Unsigned.UInt64.of_string text
      let to_text value = Unsigned.UInt64.to_string value
      let to_literal value = Unsigned.UInt64.to_string value
      let uint64_to_literal value = to_literal value
    end

    module Float = struct
      type t = float

      let of_text text = float_of_string text
      let to_text value = Printf.sprintf "%.17g" value
      let to_literal value = Printf.sprintf "%.17g" value
      let float_to_literal value = to_literal value
    end

    module Text = struct
      type t = string

      let of_text text = text
      let to_text text = text
      let to_literal text = quote text
      let string_to_literal value = to_literal value
    end

    module Blob = struct
      type t = string

      let of_text text = text
      let to_text text = text

      let to_literal bytes =
        "'\\x"
        ^ String.concat ""
            (List.map
               (fun char -> Printf.sprintf "%02x" (Char.code char))
               (List.of_seq (String.to_seq bytes)))
        ^ "'"

      let string_to_literal value = to_literal value
    end

    module Decimal = struct
      type t = float

      let of_text text = float_of_string text
      let to_text value = Printf.sprintf "%.17g" value
      let to_literal value = Printf.sprintf "%.17g" value
      let float_to_literal value = to_literal value
    end

    module Datetime = struct
      type t = string

      let of_text text = text
      let to_text text = text
      let to_literal text = quote text
      let float_to_literal seconds = Printf.sprintf "to_timestamp(%.6f)" seconds
    end

    module Json = struct
      type t = Sqlgg_trait_types.json

      let of_text text =
        Sqlgg_trait_types.convert_json (Yojson.Safe.from_string text)

      let to_text (json : t) = Yojson.Safe.to_string (json :> Yojson.Safe.t)
      let to_literal json = quote (to_text json)
      let json_to_literal value = to_literal value
    end

    module Json_path = struct
      type t = Sqlgg_trait_types.json_path

      let of_text text = Sqlgg_json_path.Json_path.parse_json_path text
      let to_text path = Sqlgg_json_path.Json_path.string_of_json_path path
      let to_literal path = quote (to_text path)
      let json_path_to_literal value = to_literal value
    end

    module One_or_all = struct
      type t = Sqlgg_trait_types.one_or_all

      let of_text text =
        match String.lowercase_ascii text with
        | "one" -> `One
        | "all" -> `All
        | text -> raise (Oops ("not one or all: " ^ text))

      let to_text = function `One -> "one" | `All -> "all"
      let to_literal value = quote (to_text value)
    end

    module Any = struct
      type t = string

      let of_text text = text
      let to_text text = text
      let to_literal text = quote text
    end
  end

  type num = Types.Int.t
  type text = Types.Text.t
  type any = Types.Any.t
  type datetime = Types.Datetime.t

  let cell decode row column =
    match row.result#getisnull row.index column with
    | true -> None
    | false -> Some (decode (row.result#getvalue row.index column))

  let required decode row column =
    match cell decode row column with
    | Some value -> value
    | None -> raise (Oops (Printf.sprintf "column %d is NULL" column))

  let get_column_Bool row column = required Types.Bool.of_text row column
  let get_column_Int row column = required Types.Int.of_text row column
  let get_column_UInt64 row column = required Types.UInt64.of_text row column
  let get_column_Text row column = required Types.Text.of_text row column
  let get_column_Any row column = required Types.Any.of_text row column
  let get_column_Float row column = required Types.Float.of_text row column
  let get_column_Decimal row column = required Types.Decimal.of_text row column

  let get_column_Datetime row column =
    required Types.Datetime.of_text row column

  let get_column_Json row column = required Types.Json.of_text row column

  let get_column_Json_path row column =
    required Types.Json_path.of_text row column

  let get_column_One_or_all row column =
    required Types.One_or_all.of_text row column

  let get_column_Bool_nullable row column = cell Types.Bool.of_text row column
  let get_column_Int_nullable row column = cell Types.Int.of_text row column

  let get_column_UInt64_nullable row column =
    cell Types.UInt64.of_text row column

  let get_column_Text_nullable row column = cell Types.Text.of_text row column
  let get_column_Any_nullable row column = cell Types.Any.of_text row column
  let get_column_Float_nullable row column = cell Types.Float.of_text row column

  let get_column_Decimal_nullable row column =
    cell Types.Decimal.of_text row column

  let get_column_Datetime_nullable row column =
    cell Types.Datetime.of_text row column

  let get_column_Json_nullable row column = cell Types.Json.of_text row column

  let get_column_Json_path_nullable row column =
    cell Types.Json_path.of_text row column

  let get_column_One_or_all_nullable row column =
    cell Types.One_or_all.of_text row column

  let get_column_bool row column = required Types.Bool.of_text row column
  let get_column_bool_nullable row column = cell Types.Bool.of_text row column
  let get_column_int64 row column = required Types.Int.of_text row column
  let get_column_int64_nullable row column = cell Types.Int.of_text row column
  let get_column_uint64 row column = required Types.UInt64.of_text row column

  let get_column_uint64_nullable row column =
    cell Types.UInt64.of_text row column

  let get_column_float row column = required Types.Float.of_text row column
  let get_column_float_nullable row column = cell Types.Float.of_text row column
  let get_column_decimal row column = required Types.Decimal.of_text row column

  let get_column_decimal_nullable row column =
    cell Types.Decimal.of_text row column

  let get_column_datetime row column =
    required Types.Datetime.of_text row column

  let get_column_datetime_nullable row column =
    cell Types.Datetime.of_text row column

  let get_column_string row column = required Types.Text.of_text row column
  let get_column_string_nullable row column = cell Types.Text.of_text row column
  let get_column_json row column = required Types.Json.of_text row column
  let get_column_json_nullable row column = cell Types.Json.of_text row column

  let get_column_json_path row column =
    required Types.Json_path.of_text row column

  let get_column_json_path_nullable row column =
    cell Types.Json_path.of_text row column

  let get_column_one_or_all row column =
    required Types.One_or_all.of_text row column

  let get_column_one_or_all_nullable row column =
    cell Types.One_or_all.of_text row column

  let start_params statement count =
    { statement; values = Array.make count Postgresql.null; next = ref 0 }

  let set params text =
    params.values.(!(params.next)) <- text;
    incr params.next

  let set_param_null params = set params Postgresql.null
  let set_param_Text params value = set params (Types.Text.to_text value)
  let set_param_Any params value = set params (Types.Any.to_text value)
  let set_param_Bool params value = set params (Types.Bool.to_text value)
  let set_param_Int params value = set params (Types.Int.to_text value)
  let set_param_UInt64 params value = set params (Types.UInt64.to_text value)
  let set_param_Float params value = set params (Types.Float.to_text value)
  let set_param_Decimal params value = set params (Types.Decimal.to_text value)

  let set_param_Datetime params value =
    set params (Types.Datetime.to_text value)

  let set_param_Json params value = set params (Types.Json.to_text value)

  let set_param_Json_path params value =
    set params (Types.Json_path.to_text value)

  let set_param_One_or_all params value =
    set params (Types.One_or_all.to_text value)

  let set_param_bool params value = set params (Types.Bool.to_text value)
  let set_param_int64 params value = set params (Types.Int.to_text value)
  let set_param_uint64 params value = set params (Types.UInt64.to_text value)
  let set_param_float params value = set params (Types.Float.to_text value)
  let set_param_decimal params value = set params (Types.Decimal.to_text value)
  let set_param_string params value = set params (Types.Text.to_text value)

  let set_param_datetime params seconds =
    let time = Unix.gmtime seconds in
    set params
      (Printf.sprintf "%04d-%02d-%02d %02d:%02d:%02d+00" (time.tm_year + 1900)
         (time.tm_mon + 1) time.tm_mday time.tm_hour time.tm_min time.tm_sec)

  let set_param_json params value = set params (Types.Json.to_text value)

  let set_param_json_path params value =
    set params (Types.Json_path.to_text value)

  let set_param_one_or_all params value =
    set params (Types.One_or_all.to_text value)

  module Make_enum (E : Sqlgg_traits.Enum) = struct
    let get_column row column = required E.inj row column
    let get_column_nullable row column = cell E.inj row column
    let set_param params value = set params (E.proj value)
    let to_literal value = quote (E.proj value)
  end

  let finish_params params =
    run params.statement.conn ~params:params.values params.statement.sql

  let no_params statement = run statement.conn statement.sql

  let rows conn sql set_params =
    Lwt.map
      (fun (result : Postgresql.result) ->
        List.init result#ntuples (fun index -> { result; index }))
      (set_params { conn; sql })

  let select conn sql set_params callback =
    Kre.Live.read sql;
    Kre.Profiler.sql sql;
    Lwt.map (List.iter callback) (rows conn sql set_params)

  let select_one_maybe conn sql set_params callback =
    Kre.Live.read sql;
    Kre.Profiler.sql sql;
    Lwt.map
      (fun rows -> Option.map callback (List.nth_opt rows 0))
      (rows conn sql set_params)

  let select_one conn sql set_params callback =
    Kre.Live.read sql;
    Kre.Profiler.sql sql;
    Lwt.bind (rows conn sql set_params) (function
      | row :: _ -> Lwt.return (callback row)
      | [] -> Lwt.fail (Oops ("no row: " ^ sql)))

  let execute conn sql set_params =
    let open Lwt.Syntax in
    let* (result : Postgresql.result) = set_params { conn; sql } in
    let* insert_id =
      let statement = String.trim sql in
      match
        String.lowercase_ascii
          (String.sub statement 0 (min 6 (String.length statement)))
      with
      | "insert" ->
          Lwt.catch
            (fun () ->
              Lwt.map
                (fun (last : Postgresql.result) ->
                  Some (Int64.of_string (last#getvalue 0 0)))
                (run conn "SELECT lastval()"))
            (fun _ -> Lwt.return_none)
      | _ -> Lwt.return_none
    in
    Kre.Live.wrote sql;
    Kre.Profiler.sql sql;
    Lwt.return
      {
        affected_rows =
          Option.value ~default:0L (Int64.of_string_opt result#cmd_tuples);
        insert_id;
      }
end

module Driver = struct
  type conn = Postgresql.connection

  let connect url =
    Sql.blocking (fun () -> new Postgresql.connection ~conninfo:url ())

  let close (conn : conn) = Sql.blocking (fun () -> conn#finish)
  let start conn = Lwt.map ignore (Sql.run conn "BEGIN")
  let commit conn = Lwt.map ignore (Sql.run conn "COMMIT")
  let rollback conn = Lwt.map ignore (Sql.run conn "ROLLBACK")
  let execute conn sql = Lwt.map ignore (Sql.run conn sql)

  let strings conn sql =
    Lwt.map
      (fun (result : Postgresql.result) ->
        List.init result#ntuples (fun index -> result#getvalue index 0))
      (Sql.run conn sql)

  let query conn sql params =
    Lwt.map
      (fun (result : Postgresql.result) ->
        List.init result#ntuples (fun row ->
            List.init result#nfields (fun field ->
                match result#getisnull row field with
                | true -> None
                | false -> Some (result#getvalue row field))))
      (Sql.run conn
         ~params:
           (Array.of_list
              (List.map (Option.value ~default:Postgresql.null) params))
         (String.concat ""
            (List.mapi
               (fun index part ->
                 match index with
                 | 0 -> part
                 | _ -> Printf.sprintf "$%d%s" index part)
               (String.split_on_char '?' sql))))
end

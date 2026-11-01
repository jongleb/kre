type t = float

let name = "time"
let of_seconds seconds = seconds
let to_seconds time = time
let compare = Float.compare

let floor_div a b =
  Float.to_int (Float.floor (Float.of_int a /. Float.of_int b))

let to_string time =
  let milliseconds = Float.to_int (Float.round (time *. 1000.)) in
  let seconds = floor_div milliseconds 1000 in
  let days = floor_div seconds 86400 in
  let clock = seconds - (days * 86400) in
  let shifted = days + 719468 in
  let era = floor_div shifted 146097 in
  let day_of_era = shifted - (era * 146097) in
  let year_of_era =
    (day_of_era - (day_of_era / 1460) + (day_of_era / 36524)
   - (day_of_era / 146096))
    / 365
  in
  let day_of_year =
    day_of_era - ((365 * year_of_era) + (year_of_era / 4) - (year_of_era / 100))
  in
  let month_index = ((5 * day_of_year) + 2) / 153 in
  let month = ((month_index + 2) mod 12) + 1 in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ"
    (year_of_era + (era * 400) + ((14 - month) / 12))
    month
    (day_of_year - (((153 * month_index) + 2) / 5) + 1)
    (clock / 3600)
    (clock mod 3600 / 60)
    (clock mod 60)
    (milliseconds - (seconds * 1000))

let of_string text =
  let invalid () =
    Error
      (Validation.fail ~rule:"format"
         "must be an RFC 3339 time, e.g. 2026-11-01T06:44:08Z")
  in
  let number start length =
    Option.bind
      (match start + length <= String.length text with
      | true -> Some (String.sub text start length)
      | false -> None)
      (fun digits ->
        Option.bind (int_of_string_opt digits) (fun value ->
            match String.for_all (fun c -> c >= '0' && c <= '9') digits with
            | true -> Some value
            | false -> None))
  in
  let separated position chars =
    Option.bind
      (match position < String.length text with
      | true -> Some text.[position]
      | false -> None)
      (fun found -> List.find_opt (Char.equal found) chars)
  in
  let fraction, zone_at =
    match separated 19 [ '.' ] with
    | None -> (0., 19)
    | Some _ ->
        let rec digits at =
          match
            separated at [ '0'; '1'; '2'; '3'; '4'; '5'; '6'; '7'; '8'; '9' ]
          with
          | Some _ -> digits (at + 1)
          | None -> at
        in
        let stop = digits 20 in
        ( Option.value ~default:0.
            (float_of_string_opt ("0." ^ String.sub text 20 (stop - 20))),
          stop )
  in
  let offset =
    match separated zone_at [ 'Z'; 'z'; '+'; '-' ] with
    | Some ('Z' | 'z') when String.length text = zone_at + 1 -> Some 0
    | Some sign when String.length text = zone_at + 6 ->
        Option.bind
          (separated (zone_at + 3) [ ':' ])
          (fun _ ->
            Option.bind
              (number (zone_at + 1) 2)
              (fun hours ->
                Option.map
                  (fun minutes ->
                    (match sign with '-' -> -1 | _ -> 1)
                    * ((hours * 60) + minutes)
                    * 60)
                  (number (zone_at + 4) 2)))
    | Some _ | None -> None
  in
  match
    ( number 0 4,
      separated 4 [ '-' ],
      number 5 2,
      separated 7 [ '-' ],
      number 8 2,
      separated 10 [ 'T'; 't'; ' ' ],
      ( number 11 2,
        separated 13 [ ':' ],
        number 14 2,
        separated 16 [ ':' ],
        number 17 2 ),
      offset )
  with
  | ( Some year,
      Some _,
      Some month,
      Some _,
      Some day,
      Some _,
      (Some hours, Some _, Some minutes, Some _, Some seconds),
      Some offset )
    when month >= 1 && month <= 12 && day >= 1 && day <= 31 && hours < 24
         && minutes < 60 && seconds < 61 ->
      let shifted = year - ((14 - month) / 12) in
      let era = floor_div shifted 400 in
      let year_of_era = shifted - (era * 400) in
      let day_of_year = (((153 * ((month + 9) mod 12)) + 2) / 5) + day - 1 in
      let days =
        (era * 146097)
        + ((year_of_era * 365) + (year_of_era / 4) - (year_of_era / 100)
         + day_of_year)
        - 719468
      in
      Ok
        (Float.of_int
           ((days * 86400) + (hours * 3600) + (minutes * 60) + seconds - offset)
        +. fraction)
  | _ -> invalid ()

let to_json time = Jsonkit.declassify (`String (to_string time))

let of_json json =
  match Jsonkit.classify json with
  | `String text -> Validation.ok_exn (of_string text)
  | _ ->
      raise
        (Validation.Invalid (Validation.fail ~rule:"type" "must be a string"))

let t_jsonschema =
  `Assoc [ ("type", `String "string"); ("format", `String "date-time") ]

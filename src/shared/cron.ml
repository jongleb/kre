type t = {
  minutes : int list;
  hours : int list;
  days : int list;
  months : int list;
  weekdays : int list;
}

let field ~name ~low ~high text =
  let number raw =
    match int_of_string_opt raw with
    | Some n when n >= low && n <= high -> Ok n
    | Some n -> Error (Printf.sprintf "%s %d is outside %d-%d" name n low high)
    | None -> Error (Printf.sprintf "%s: %S is not a number" name raw)
  in
  let range raw =
    match String.split_on_char '-' raw with
    | [ "*" ] -> Ok (low, high)
    | [ single ] -> Result.map (fun n -> (n, n)) (number single)
    | [ first; last ] ->
        Result.bind (number first) (fun first ->
            Result.bind (number last) (fun last ->
                if first <= last then Ok (first, last)
                else Error (Printf.sprintf "%s range %s is backwards" name raw)))
    | _ -> Error (Printf.sprintf "%s: bad range %S" name raw)
  in
  let part raw =
    let span, step =
      match String.split_on_char '/' raw with
      | [ span; step ] -> (span, int_of_string_opt step)
      | _ -> (raw, Some 1)
    in
    match step with
    | Some step when step >= 1 ->
        Result.map
          (fun (first, last) ->
            List.filter
              (fun n -> (n - first) mod step = 0)
              (List.init (last - first + 1) (fun offset -> first + offset)))
          (range span)
    | Some _ | None -> Error (Printf.sprintf "%s: bad step in %S" name raw)
  in
  List.fold_right
    (fun raw collected ->
      Result.bind (part raw) (fun values ->
          Result.map (fun collected -> values @ collected) collected))
    (String.split_on_char ',' text)
    (Ok [])
  |> Result.map (List.sort_uniq Int.compare)

let of_string text =
  match
    List.filter (fun part -> part <> "") (String.split_on_char ' ' text)
  with
  | [ minutes; hours; days; months; weekdays ] ->
      Result.bind (field ~name:"minute" ~low:0 ~high:59 minutes) (fun minutes ->
          Result.bind (field ~name:"hour" ~low:0 ~high:23 hours) (fun hours ->
              Result.bind (field ~name:"day" ~low:1 ~high:31 days) (fun days ->
                  Result.bind (field ~name:"month" ~low:1 ~high:12 months)
                    (fun months ->
                      Result.map
                        (fun weekdays ->
                          { minutes; hours; days; months; weekdays })
                        (field ~name:"weekday" ~low:0 ~high:6 weekdays)))))
  | _ ->
      Error "a cron expression has five fields: minute hour day month weekday"

let of_string_exn text =
  match of_string text with
  | Ok cron -> cron
  | Error message -> invalid_arg ("Cron.of_string_exn: " ^ message)

let next cron ~after =
  let civil days =
    let z = days + 719468 in
    let era = (if z >= 0 then z else z - 146096) / 146097 in
    let day_of_era = z - (era * 146097) in
    let year_of_era =
      (day_of_era - (day_of_era / 1460) + (day_of_era / 36524)
     - (day_of_era / 146096))
      / 365
    in
    let day_of_year =
      day_of_era
      - ((365 * year_of_era) + (year_of_era / 4) - (year_of_era / 100))
    in
    let shifted_month = ((5 * day_of_year) + 2) / 153 in
    ( day_of_year - (((153 * shifted_month) + 2) / 5) + 1,
      if shifted_month < 10 then shifted_month + 3 else shifted_month - 9 )
  in
  let first = int_of_float (Float.floor (after /. 60.)) + 1 in
  let rec search minute remaining =
    let days =
      if minute >= 0 then minute / 1440 else ((minute + 1) / 1440) - 1
    in
    let in_day = minute - (days * 1440) in
    let day, month = civil days in
    let weekday = ((days mod 7) + 11) mod 7 in
    match
      ( remaining,
        List.mem (in_day mod 60) cron.minutes
        && List.mem (in_day / 60) cron.hours
        && List.mem day cron.days && List.mem month cron.months
        && List.mem weekday cron.weekdays )
    with
    | _, true -> Some (float_of_int (minute * 60))
    | 0, false -> None
    | _, false -> search (minute + 1) (remaining - 1)
  in
  search first (366 * 24 * 60 * 8)

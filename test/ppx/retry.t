[@@retry n] on any function, like Spring's @Retryable: the body runs again
when it raises, up to n times; [@@backoff s] is the first pause, doubled each
time.

  $ cat > input.ml <<'ML'
  > let fetch ~city () : string Lwt.t = Weather.get city
  > [@@retry 3] [@@backoff 0.1]
  > 
  > module Service = struct
  >   let ping () = Http.ping () [@@retry 2]
  > end
  > ML
  $ ./pp.exe -impl input.ml
  let fetch ~city () : string Lwt.t=
    Kre.Retry.run ~backoff:0.1 ~attempts:3 (fun () -> Weather.get city)
  module Service =
    struct let ping () = Kre.Retry.run ~attempts:2 (fun () -> Http.ping ()) end

Errors say where it goes.

  $ cat > input.ml <<'ML'
  > let fetch = Weather.get [@@retry 3]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 1, characters 24-35:
  1 | let fetch = Weather.get [@@retry 3]
                              ^^^^^^^^^^^
  Error: [@@retry] repeats a call; put it on a function: let f x = … [@@retry 3]
  [1]
  $ cat > input.ml <<'ML'
  > let fetch () = Weather.get () [@@retry "three"]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 1, characters 30-47:
  1 | let fetch () = Weather.get () [@@retry "three"]
                                    ^^^^^^^^^^^^^^^^^
  Error: [@@retry] takes the number of attempts: [@@retry 3]
  [1]
  $ cat > input.ml <<'ML'
  > let fetch () = Weather.get () [@@backoff 0.1]
  > ML
  $ ./pp.exe -impl input.ml
  File "input.ml", line 1, characters 30-45:
  1 | let fetch () = Weather.get () [@@backoff 0.1]
                                    ^^^^^^^^^^^^^^^
  Error: [@@backoff] sets the pause between retries; add [@@retry 3]
  [1]

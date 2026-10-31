[%wire] scans directories at build time: modules with Make or module type S
are providers, [@@@controller] files are consumers, anything else is left
alone.

  $ mkdir app
  $ cat > app/repo.ml <<'ML'
  > module type S = sig val all : unit -> int list end
  > module Make () = struct let all () = [ 1 ] end
  > ML
  $ cat > app/clock.ml <<'ML'
  > module type S = sig val now : unit -> float end
  > let now () = 0.
  > ML
  $ cat > app/report.ml <<'ML'
  > module type S = sig val text : unit -> string end
  > module Make (Repo : Repo.S) (C : Clock.S) = struct
  >   let text () = "report"
  >   let on_start () = Lwt.return_unit
  > end
  > ML
  $ cat > app/helpers.ml <<'ML'
  > let twice x = x * 2
  > ML
  $ cat > app/reports_controller.ml <<'ML'
  > [@@@controller "reports"]
  > let show (module Report : Report.S) () : string Lwt.t = Lwt.return (Report.text ())
  > [@@get]
  > ML
  $ cat > main.ml <<'ML'
  > let app = [%wire "app"]
  > ML
  $ ../ppx/pp.exe -impl main.ml
  let app =
    let module Repo = (Repo.Make)() in
      let module Report = ((Report.Make)(Repo))(Clock) in
        Forge.Wiring.make
          ~controllers:[Reports_controller.register (module Report)]
          ~on_start:[Report.on_start] ~on_shutdown:[] ~jobs:[] ~health:[] ()

A dependency nobody provides is a build error.

  $ mv app/clock.ml clock.ml.off
  $ ../ppx/pp.exe -impl main.ml
  File "./app/report.ml", line 1, characters 0-49:
  Error: Report needs Clock.S, but no provider gives it: add a module with Make or module type S that implements it
  [1]
  $ mv clock.ml.off app/clock.ml

Two providers of one interface: a build error until one is [@@@primary].

  $ cat > app/fake_clock.ml <<'ML'
  > module Make () : Clock.S = struct let now () = 1. end
  > ML
  $ ../ppx/pp.exe -impl main.ml
  File "./app/report.ml", line 1, characters 0-49:
  Error: Report needs Clock.S and 2 providers give it (Clock, Fake_clock); mark one [@@@primary] or name the parameter after one
  [1]
  $ printf '[@@@primary]\n' | cat - app/fake_clock.ml > primary.ml && mv primary.ml app/fake_clock.ml
  $ ../ppx/pp.exe -impl main.ml | grep 'Report.Make'
        let module Report = ((Report.Make)(Repo))(Fake_clock) in

Without [@@@primary], naming the parameter after a provider picks it, as
Spring falls back to the bean name.

  $ sed -i.bak '/primary/d' app/fake_clock.ml && rm app/fake_clock.ml.bak
  $ sed -i.bak 's/(C : Clock.S)/(Clock : Clock.S)/' app/report.ml && rm app/report.ml.bak
  $ ../ppx/pp.exe -impl main.ml | grep 'Report.Make'
        let module Report = ((Report.Make)(Repo))(Clock) in

A cycle is a build error.

  $ rm app/fake_clock.ml
  $ cat > app/clock.ml <<'ML'
  > module type S = sig val now : unit -> float end
  > module Make (Report : Report.S) = struct let now () = 0. end
  > ML
  $ ../ppx/pp.exe -impl main.ml
  File "./app/clock.ml", line 1, characters 0-47:
  Error: dependency cycle: Clock -> Report -> Clock
  [1]

An [@@on_event] listener needs a bus provider.

  $ cat > app/clock.ml <<'ML'
  > module type S = sig val now : unit -> float end
  > let now () = 0.
  > let tick () = Lwt.return_unit [@@on_event Topics.tick]
  > ML
  $ ../ppx/pp.exe -impl main.ml
  File "./app/clock.ml", line 1, characters 0-47:
  Error: Clock needs Forge.Events.S, but no provider gives it: add a module with Make or module type S that implements it
  [1]
A cron expression is checked at build time.

  $ cat > app/clock.ml <<'ML'
  > module type S = sig val now : unit -> float end
  > let now () = 0.
  > let sweep () = Lwt.return_unit [@@cron "61 * * * *"]
  > ML
  $ ../ppx/pp.exe -impl main.ml
  File "./app/clock.ml", line 3, characters 31-52:
  Error: [@cron "61 * * * *"]: minute 61 is outside 0-59
  [1]

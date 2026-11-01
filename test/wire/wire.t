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
        Kre.Wiring.make
          ~controllers:[Reports_controller.register (module Report)]
          ~on_start:[Report.on_start] ~on_shutdown:[] ~jobs:[] ~health:[]
          ~commands:[]
          ~beans:[{ Kre.Actuator.name = "Clock"; needs = [] };
                 { Kre.Actuator.name = "Repo"; needs = [] };
                 { Kre.Actuator.name = "Report"; needs = ["Repo"; "Clock"] };
                 { Kre.Actuator.name = "Reports_controller"; needs = ["Report"]
                 }] ()

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

Without [@@@primary], naming the parameter after a provider picks it.

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
  Error: Clock needs Kre.Events.S, but no provider gives it: add a module with Make or module type S that implements it
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
A [@@@fallback] provider stands in only when nothing else gives the
interface.

  $ cat > app/clock.ml <<'ML'
  > module type S = sig val now : unit -> float end
  > ML
  $ cat > app/frozen_clock.ml <<'ML'
  > [@@@fallback]
  > module Make () : Clock.S = struct let now () = 0. end
  > ML
  $ ../ppx/pp.exe -impl main.ml | grep -i clock
    let module Frozen_clock = (Frozen_clock.Make)() in
        let module Report = ((Report.Make)(Repo))(Frozen_clock) in
            ~beans:[{ Kre.Actuator.name = "Frozen_clock"; needs = [] };
                     needs = ["Repo"; "Frozen_clock"]
  $ cat > app/system_clock.ml <<'ML'
  > module Make () : Clock.S = struct let now () = Unix.gettimeofday () end
  > ML
  $ ../ppx/pp.exe -impl main.ml | grep -i clock
      let module System_clock = (System_clock.Make)() in
        let module Report = ((Report.Make)(Repo))(System_clock) in
                   { Kre.Actuator.name = "System_clock"; needs = [] };
                     needs = ["Repo"; "System_clock"]

[@@@decorates I.S] wraps the provider of I.S: the decorator gets the
original, everyone else gets the decorator. Two decorators chain in file
order.

  $ rm app/frozen_clock.ml
  $ cat > app/logged_clock.ml <<'ML'
  > [@@@decorates Clock.S]
  > module Make (Clock : Clock.S) = struct let now () = Clock.now () end
  > ML
  $ cat > app/timed_clock.ml <<'ML'
  > [@@@decorates Clock.S]
  > module Make (Clock : Clock.S) = struct let now () = Clock.now () end
  > ML
  $ ../ppx/pp.exe -impl main.ml | grep 'let module'
    let module System_clock = (System_clock.Make)() in
      let module Logged_clock = (Logged_clock.Make)(System_clock) in
        let module Repo = (Repo.Make)() in
          let module Timed_clock = (Timed_clock.Make)(Logged_clock) in
            let module Report = ((Report.Make)(Repo))(Timed_clock) in

A decorator must take what it wraps.

  $ cat > app/timed_clock.ml <<'ML'
  > [@@@decorates Clock.S]
  > module Make () = struct let now () = 0. end
  > ML
  $ ../ppx/pp.exe -impl main.ml
  File "./app/timed_clock.ml", line 1, characters 0-22:
  Error: Timed_clock decorates Clock.S, so its Make takes the original: module Make (Inner : Clock.S) = …
  [1]
  $ rm app/timed_clock.ml app/logged_clock.ml

A (Notifiers : Kre.Wiring.ALL with type t = (module I.S)) parameter gets
every provider of I.S, but not the provider itself.

  $ cat > app/clocks.ml <<'ML'
  > module Make (Clocks : Kre.Wiring.ALL with type t = (module Clock.S)) : Clock.S = struct
  >   let now () = List.fold_left (fun _ (module C : Clock.S) -> C.now ()) 0. Clocks.all
  > end
  > [@@@primary]
  > ML
  $ ../ppx/pp.exe -impl main.ml | grep -A 8 'module Clocks'
      let module Clocks =
        (Clocks.Make)(struct
                        type t = (module Clock.S)
                        let all = [((module System_clock) : (module Clock.S))]
                      end) in
        let module Repo = (Repo.Make)() in
          let module Report = ((Report.Make)(Repo))(Clocks) in
            Kre.Wiring.make
              ~controllers:[Reports_controller.register (module Report)]

[@@@profile "test"] swaps a provider when KRE_ENV is "test". It needs a
provider without a profile for the other environments.

  $ rm app/clocks.ml
  $ cat > app/test_clock.ml <<'ML'
  > [@@@profile "test"]
  > module Make () : Clock.S = struct let now () = 42. end
  > ML
  $ ../ppx/pp.exe -impl main.ml | grep -B 1 -A 6 'Kre.Wiring.profile'
      let module System_clock = (val
        (match Kre.Wiring.profile () with
         | "test" -> ((module (Test_clock.Make)()) : (module Clock.S))
         | _ -> ((module (System_clock.Make)()) : (module Clock.S)) : (module
                                                                      Clock.S)))
        in
        let module Report = ((Report.Make)(Repo))(System_clock) in
          Kre.Wiring.make
  $ cat > app/other_test_clock.ml <<'ML'
  > [@@@profile "test"]
  > module Make () : Clock.S = struct let now () = 43. end
  > ML
  $ ../ppx/pp.exe -impl main.ml
  File "./app/test_clock.ml", line 1, characters 0-19:
  Error: Other_test_clock and Test_clock both have [@@@profile "test"] for Clock.S; keep one
  [1]
  $ rm app/other_test_clock.ml app/system_clock.ml
  $ ../ppx/pp.exe -impl main.ml
  File "./app/test_clock.ml", line 1, characters 0-19:
  Error: Test_clock has [@@@profile "test"], but Clock.S has no provider without a profile for the other environments; add one
  [1]

A provider picked at start-up exposes only its interface, so its hooks would
be lost: a build error.

  $ cat > app/system_clock.ml <<'ML'
  > module Make () : Clock.S = struct
  >   let now () = Unix.gettimeofday ()
  >   let on_start () = Lwt.return_unit
  > end
  > ML
  $ ../ppx/pp.exe -impl main.ml
  File "./app/system_clock.ml", lines 1-4, characters 0-3:
  Error: System_clock is picked by KRE_ENV at start-up and seen only as Clock.S, so its on_start, on_shutdown and [@@on_event], [@@job], [@@health] or schedule functions would never run; move them to a provider of their own
  [1]

A controller with [@@ability] needs Kre.Token.S.

  $ rm app/test_clock.ml
  $ cat > app/tokens.ml <<'ML'
  > module Make (Repo : Repo.S) : Kre.Token.S = struct end
  > ML
  $ cat > app/api_controller.ml <<'ML'
  > [@@@controller "api"]
  > let ping () : string Lwt.t = Lwt.return "pong" [@@get] [@@ability "ping"]
  > ML
  $ ../ppx/pp.exe -impl main.ml | grep 'Api_controller.register'
              ~controllers:[Api_controller.register (module Tokens);

[%wire] reads [%%resource] controllers too.

  $ cat > app/repos_controller.ml <<'ML'
  > [@@@controller "repos"]
  > [%%resource { service = (module Repo : Repo.S); entity = Book; actions = [ Show ] }]
  > ML
  $ ../ppx/pp.exe -impl main.ml | grep 'Repos_controller.register'
                           Repos_controller.register (module Repo)]

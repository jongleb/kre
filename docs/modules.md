# Modules

Modules come from OCaml itself: a module is a unit of code, `.mli` is its exports, a dune library is a package boundary, `bin/main.ml` is where the application is assembled. There is no separate "Kre module" entity.

A provider with dependencies is a functor: its arguments are what it imports.

<!-- $MDX file=../examples/cats/db/cats_db_service.mli -->
```ocaml
module Make (Db : Kre.Db.S with type conn = Kre_db_mariadb.Client.t) : sig
  include Cats_service.S

  val reset : unit -> unit Lwt.t
end
```

Application happens in the composition root: `module Cats = Cats_db_service.Make (Db)`, then `Cats_controller.register (module Cats)`. The order of functor application is the initialization order; cycles cannot be expressed.

You do not need to assemble this by hand. `[%wire]` in `main.ml` assembles the application: at build time the ppx reads the directories, finds providers (modules with `Make` or `module type S`), sorts them by dependencies, applies the functors and registers the controllers. A missing provider, two candidates without `[@@@primary]`, a cycle: each is a compile error pointing to the place in the code.

<!-- $MDX file=../examples/cats/bin/main.ml -->
```ocaml
let () =
  let app = [%wire] in
  let actuator =
    Kre.Actuator.make ~checks:app.health ~beans:app.beans
      ~env:(Config.pairs Settings.config)
      app.controllers
  in
  Kre.App.run ~port:Settings.config.port
    ~middleware:
      [ Dream.logger; actuator.metrics; Web.use ~dir:Settings.config.web ]
    ~on_start:app.on_start ~on_shutdown:app.on_shutdown
    (actuator.controller :: Kre.Live.controller :: app.controllers)
```

A database provider with an `on_start` hook (migrations at startup):

<!-- $MDX file=../examples/cats/db/database.ml -->
```ocaml
module Make (Settings : Settings.S) = struct
  include
    Kre.Db.Make
      (Kre_db_mariadb.Driver)
      (struct
        let url = Settings.database_url
        let size = 4
      end)

  let on_start () =
    with_conn (fun conn ->
        Lwt.map ignore
          (Kre.Migration.up
             (module Kre_db_mariadb.Driver)
             conn
             (Result.get_ok (Kre.Migration.of_files [%embed_dir "migrations"]))))

  let ping () =
    Lwt.catch
      (fun () ->
        with_conn (fun conn ->
            Lwt.map
              (fun _ -> Ok ())
              (Kre_db_mariadb.Driver.strings conn "SELECT 1")))
      (fun exn -> Lwt.return_error (Printexc.to_string exn))
  [@@health "db"]
end
```

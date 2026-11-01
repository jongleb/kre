(lang dune 3.21)

(using melange 0.1)

(using mdx 0.4)

; Pages are written in mlx: OCaml with JSX.

(dialect
 (name mlx)
 (implementation
  (extension mlx)
  (merlin_reader mlx)
  (format
   (run ocamlformat-mlx %{input-file}))
  (preprocess
   (run mlx-pp %{input-file}))))

(name kre)

(generate_opam_files true)

(source
 (github jongleber/forge))

(authors "Gleb")

(maintainers "Gleb")

(license ISC)

(package
 (name kre)
 (synopsis "NestJS-like server runtime on Dream")
 (depends
  (ocaml
   (and
    (>= 5.5)
    (< 5.6)))
  (dream
   (>= 1.0.0))
  (routes
   (>= 2.0.0))
  lwt
  (jsonkit
   (>= 1.1.0))
  (alcotest :with-test)
  (alcotest-lwt :with-test)))

(package
 (name kre-ppx)
 (synopsis "Kre ppx: controller, dto, config, table")
 (depends
  (ocaml
   (and
    (>= 5.5)
    (< 5.6)))
  (ppxlib
   (>= 0.38.0))
  (jsonkit
   (>= 1.1.0))
  (ppx_expect :with-test)))

(package
 (name kre-client)
 (synopsis "Kre Melange client: Http, Router, Path, Search")
 (depends
  (ocaml
   (and
    (>= 5.5)
    (< 5.6)))
  (melange
   (>= 7.0.0))
  (jsonkit-melange
   (>= 1.1.0))
  (kre
   (= :version))
  cohttp-lwt-unix
  lwt
  uri
  (reason-react
   (>= 0.17.0))
  (reason-react-ppx
   (>= 0.17.0))
  (mlx
   (and
    (>= 0.11)
    :with-test))))

(package
 (name kre-cli)
 (synopsis "The kre command-line tool")
 (depends
  (ocaml
   (and
    (>= 5.5)
    (< 5.6)))
  (cmdliner
   (>= 2.0.0))
  (kre
   (= :version))
  yojson
  dream
  (kre-db-mariadb
   (= :version))))

(package
 (name kre-db-mariadb)
 (synopsis "MariaDB driver and sqlgg traits for Kre.Db")
 (depends
  (ocaml
   (and
    (>= 5.5)
    (< 5.6)))
  (kre
   (= :version))
  (mariadb
   (>= 2.2.0))
  (sqlgg
   (>= 20260721))
  lwt
  uri))

(package
 (name kre-db-postgresql)
 (synopsis "PostgreSQL driver (libpq) and sqlgg traits for Kre.Db")
 (depends
  (ocaml
   (and
    (>= 5.5)
    (< 5.6)))
  (kre
   (= :version))
  (postgresql
   (>= 5.0))
  (sqlgg
   (>= 20260721))
  integers
  yojson
  lwt))

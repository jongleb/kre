(lang dune 3.21)

(using melange 0.1)

(name forge)

(generate_opam_files true)

(source
 (github jongleber/forge))

(authors "Gleb")

(maintainers "Gleb")

(license ISC)

(package
 (name forge)
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
 (name forge-ppx)
 (synopsis "Forge ppx: controller, dto, config, table")
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
 (name forge-client)
 (synopsis "Forge Melange client: Http, Router, Path, Search")
 (depends
  (ocaml
   (and
    (>= 5.5)
    (< 5.6)))
  (melange
   (>= 7.0.0))
  (jsonkit-melange
   (>= 1.1.0))
  (forge
   (= :version))
  cohttp-lwt-unix
  lwt
  uri))

(package
 (name forge-cli)
 (synopsis "The forge command-line tool")
 (depends
  (ocaml
   (and
    (>= 5.5)
    (< 5.6)))
  (cmdliner
   (>= 2.0.0))
  (forge
   (= :version))
  yojson
  dream))

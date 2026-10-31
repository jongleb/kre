A link to a route is checked against the route's params and search types.

  $ cat > dune-project <<'EOF2'
  > (lang dune 3.21)
  > (using melange 0.1)
  > EOF2
  $ cat > dune <<'EOF2'
  > (library
  >  (name pages)
  >  (modes melange)
  >  (libraries forge-client reason-react)
  >  (preprocess (pps melange.ppx reason-react-ppx forge-ppx)))
  > EOF2
  $ cat > pages.ml <<'EOF2'
  > let root = Forge_client.Router.root ()
  > type params = { id : int } [@@deriving params ~path:"/cats/:id"]
  > let show =
  >   Forge_client.Router.child root ~path:params_path ~search:Forge_client.Search.none
  >     ~loader:Forge_client.Router.no_data
  >     ~component:(fun ~data:() ~params:_ ~search:() -> React.null)
  > let ok = Forge_client.Router.link show ~params:{ id = 1 } ~search:() ~children:React.null
  > EOF2
  $ dune build 2>&1 && echo compiles
  compiles

Wrong params do not compile.

  $ cat >> pages.ml <<'EOF2'
  > let wrong = Forge_client.Router.link show ~params:() ~search:() ~children:React.null
  > EOF2
  $ dune build 2>&1 | grep -A1 "^Error"
  Error: This expression should not be a unit literal, the expected type is
         params

A [%path] with parameters must come from [@@deriving params].

  $ cat > pages.ml <<'EOF2'
  > let path = [%path "/cats/:id"]
  > EOF2
  $ dune build 2>&1 | grep -A1 "^Error"
  Error: [%path "/cats/:id"] has parameters; declare them with type params = { … } [@@deriving params ~path:"/cats/:id"]

Params and path must agree.

  $ cat > pages.ml <<'EOF2'
  > type params = { id : int; slug : string } [@@deriving params ~path:"/cats/:id"]
  > EOF2
  $ dune build 2>&1 | grep -A2 "^Error"
  Error: path /cats/:id and the record disagree: segments without a field: []; fields without a segment: [slug]

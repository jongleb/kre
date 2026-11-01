# Client and router

`kre client` generates a module per controller; the same file builds both under Melange (fetch) and in native (cohttp). Page routes are described by values, and `Router.link` and `Router.href` check `params` and `search` by types.

<!-- $MDX file=../examples/cats/client_js/routes.ml -->
```ocaml
let root = Kre_client.Router.root ~layout:Pages.layout ()

module Cats = struct
  let index =
    Kre_client.Router.child ~live:Cats_client.Live.find_all root
      ~path:[%path "/cats"] ~search:Cat_search.codec
      ~loader:(fun () search -> Cats_client.find_all ~search)
      ~component:Pages.index

  type params = { id : Cat.Id.t } [@@deriving params ~path:"/cats/:id"]

  let show =
    Kre_client.Router.child root ~path:params_path
      ~search:Kre_shared.Search.none
      ~loader:(fun { id } () -> Cats_client.find_one ~id)
      ~component:Pages.show
end

let router = Kre_client.Router.make [ Any Cats.index; Any Cats.show ]
```

<!-- $MDX file=../examples/cats/client_js/pages.mlx -->
```ocaml
let layout ~children = <main>children</main>

let index ~data ~params:() ~search:_ =
  match data with
  | Error error -> React.string (Kre_client.Error.message error)
  | Ok cats ->
      <ul>
        (React.array
           (Array.of_list
              (List.map
                 (fun (cat : Cat.t) ->
                   <li>(React.string (Cat.Name.to_repr cat.name))</li>)
                 cats)))
      </ul>

let show ~data ~params:_ ~search:() =
  match data with
  | Error error -> React.string (Kre_client.Error.message error)
  | Ok (cat : Cat.t) -> <h1>(React.string (Cat.Name.to_repr cat.name))</h1>
```


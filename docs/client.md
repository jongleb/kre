# Клиент и роутер

`forge client` генерирует модуль на каждый контроллер; один и тот же файл собирается и под Melange (fetch), и в native (cohttp). Маршруты страниц описываются значениями, `Router.link` и `Router.href` проверяют `params` и `search` типами.

<!-- $MDX file=../examples/cats/client_js/routes.ml -->
```ocaml
let root = Forge_client.Router.root ~layout:Pages.layout ()

module Cats = struct
  type search = { limit : int; [@default 20] breed : string option }
  [@@deriving search]

  let index =
    Forge_client.Router.child ~live:Cats_client.Live.find_all root
      ~path:[%path "/cats"] ~search:search_codec
      ~loader:(fun () search -> Cats_client.find_all ~limit:search.limit ())
      ~component:Pages.index

  type params = { id : Cat.Id.t } [@@deriving params ~path:"/cats/:id"]

  let show =
    Forge_client.Router.child root ~path:params_path
      ~search:Forge_client.Search.none
      ~loader:(fun { id } () -> Cats_client.find_one ~id)
      ~component:Pages.show
end

let router = Forge_client.Router.make [ Any Cats.index; Any Cats.show ]
```

<!-- $MDX file=../examples/cats/client_js/pages.ml -->
```ocaml
let layout ~children = main ~children:[ children ] () [@JSX]

let index ~data ~params:() ~search:_ =
  match data with
  | Error error -> React.string (Forge_client.Error.message error)
  | Ok cats ->
      ul
        ~children:
          [
            React.array
              (Array.of_list
                 (List.map
                    (fun (cat : Cat.t) ->
                      (li
                         ~children:[ React.string (Cat.Name.to_repr cat.name) ]
                         () [@JSX]))
                    cats));
          ]
        () [@JSX]

let show ~data ~params:_ ~search:() =
  match data with
  | Error error -> React.string (Forge_client.Error.message error)
  | Ok (cat : Cat.t) ->
      h1 ~children:[ React.string (Cat.Name.to_repr cat.name) ] () [@JSX]
```


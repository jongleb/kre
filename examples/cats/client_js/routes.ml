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

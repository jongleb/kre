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

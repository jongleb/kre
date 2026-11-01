let root = Forge_client.Router.root ~layout:Pages.layout ()

module Cats = struct
  type params = { id : Cat.Id.t } [@@deriving params ~path:"/cats/:id"]

  let show =
    Forge_client.Router.child ~live:Cats_client.Live.find_one root
      ~path:params_path ~search:Forge_client.Search.none
      ~loader:(fun { id } () -> Cats_client.find_one ~id)
      ~component:Pages.cat

  let index =
    Forge_client.Router.child ~live:Cats_client.Live.available root
      ~path:[%path "/cats"] ~search:Forge_client.Search.none
      ~loader:(fun () () -> Cats_client.available ())
      ~component:
        (Pages.cats ~link:(fun (cat : Cat.t) children ->
             Forge_client.Router.link show ~params:{ id = cat.id } ~search:()
               ~children))
end

let adoptions =
  Forge_client.Router.child ~live:Adoptions_client.Live.mine root
    ~path:[%path "/adoptions"] ~search:Forge_client.Search.none
    ~loader:(fun () () -> Adoptions_client.mine ())
    ~component:Pages.adoptions

let login =
  Forge_client.Router.child root ~path:[%path "/login"]
    ~search:Forge_client.Search.none ~loader:Forge_client.Router.no_data
    ~component:(fun ~data:() ~params:() ~search:() ->
      React.createElement Pages.Login.make
        (Pages.Login.makeProps
           ~on_login:(fun (session : Session.t) ->
             Forge_client.Http.headers :=
               [ ("Authorization", "Bearer " ^ session.token) ];
             Forge_client.Router.navigate Cats.index ~params:() ~search:())
           ()))

let router =
  Forge_client.Router.make
    [ Any Cats.index; Any Cats.show; Any adoptions; Any login ]

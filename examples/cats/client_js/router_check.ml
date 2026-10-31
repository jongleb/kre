let line label value = Js.log (label ^ " " ^ value)

let () =
  line "href"
    (Forge_client.Router.href Routes.Cats.show ~params:{ id = 42 } ~search:());
  line "href"
    (Forge_client.Router.href Routes.Cats.index ~params:()
       ~search:{ limit = 5; breed = Some "maine coon" });
  line "match"
    (Option.fold ~none:"none"
       ~some:(fun (params : Routes.Cats.params) -> string_of_int params.id)
       (Forge_client.Path.match_ Routes.Cats.params_path [ "cats"; "7" ]));
  line "match"
    (Option.fold ~none:"none"
       ~some:(fun (params : Routes.Cats.params) -> string_of_int params.id)
       (Forge_client.Path.match_ Routes.Cats.params_path [ "cats"; "seven" ]));
  line "search"
    (Result.fold
       ~error:(fun errors ->
         String.concat ","
           (List.map
              (fun (error : Forge_shared.Validation.error) ->
                String.concat "." error.path ^ ":" ^ error.rule)
              (Forge_shared.Validation.to_list errors)))
       ~ok:(fun (search : Routes.Cats.search) ->
         string_of_int search.limit ^ "/"
         ^ Option.value search.breed ~default:"-")
       (Forge_client.Search.parse Routes.Cats.search_codec "?breed=persian"));
  line "search"
    (Result.fold
       ~error:(fun errors ->
         String.concat ","
           (List.map
              (fun (error : Forge_shared.Validation.error) ->
                String.concat "." error.path ^ ":" ^ error.rule)
              (Forge_shared.Validation.to_list errors)))
       ~ok:(fun _ -> "ok")
       (Forge_client.Search.parse Routes.Cats.search_codec "?limit=many"));
  line "link"
    (ReactDOMServer.renderToStaticMarkup
       (Forge_client.Router.link Routes.Cats.show ~params:{ id = 3 } ~search:()
          ~children:(React.string "tom")));
  line "view"
    (ReactDOMServer.renderToStaticMarkup
       (React.createElement Forge_client.Router.View.make
          (Forge_client.Router.View.makeProps ~router:Routes.router
             ~server_url:"/cats/3" ~pending:(React.string "loading") ())));
  line "view"
    (ReactDOMServer.renderToStaticMarkup
       (React.createElement Forge_client.Router.View.make
          (Forge_client.Router.View.makeProps ~router:Routes.router
             ~server_url:"/dogs" ())))

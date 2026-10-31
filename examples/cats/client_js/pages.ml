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

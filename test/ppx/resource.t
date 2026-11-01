[%%resource] writes a controller's CRUD handlers over a service; the
controller pass then turns them into routes.

  $ cat > books_controller.ml <<'ML'
  > [@@@controller "books"]
  > [%%resource
  > {
  >   service = (module Books : Books.S);
  >   entity = Book;
  >   actions = [ Index; Show; Create Book_draft; Remove ];
  > }]
  > ML
  $ ./pp.exe -impl books_controller.ml | sed -n '1,/^module Paths/p' | sed '$d'
  let index ((module Books)  : (module Books.S))
    ~page:(page : ((Kre_shared.Page.Request.t)[@search ])) () :
    Book.t Kre_shared.Page.t Lwt.t= Books.page page
  let show ((module Books)  : (module Books.S))
    ~book:(book : ((Book.t)[@load Books.find])) : Book.t Lwt.t= Lwt.return book
  let create ((module Books)  : (module Books.S)) ~body:(body : Book_draft.t) :
    Book.t Lwt.t= Books.create body
  let remove ((module Books)  : (module Books.S))
    ~book:(book : ((Book.t)[@load Books.find])) : unit Lwt.t= Books.remove book

The service is a dependency as a handler writes it.

  $ cat > books_controller.ml <<'ML'
  > [@@@controller "books"]
  > [%%resource { service = Books; entity = Book; actions = [ Show ] }]
  > ML
  $ ./pp.exe -impl books_controller.ml
  File "books_controller.ml", line 2, characters 24-29:
  2 | [%%resource { service = Books; entity = Book; actions = [ Show ] }]
                              ^^^^^
  Error: service names the dependency the way a handler takes it: (module Cats : Cats_service.S)
  [1]

Actions are a closed list.

  $ cat > books_controller.ml <<'ML'
  > [@@@controller "books"]
  > [%%resource { service = (module Books : Books.S); entity = Book; actions = [ Update ] }]
  > ML
  $ ./pp.exe -impl books_controller.ml
  File "books_controller.ml", line 2, characters 77-83:
  2 | [%%resource { service = (module Books : Books.S); entity = Book; actions = [ Update ] }]
                                                                                   ^^^^^^
  Error: an action is Index, Index Filter, Show, Create Draft or Remove
  [1]

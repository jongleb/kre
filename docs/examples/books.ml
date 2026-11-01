module type S = sig
  val page :
    Book_filter.t -> Kre_shared.Page.Request.t -> Book.t Kre_shared.Page.t Lwt.t

  val find : Book.Id.t -> Book.t option Lwt.t
  val create : Book_draft.t -> Book.t Lwt.t
  val remove : Book.t -> unit Lwt.t
end

module Make () : S = struct
  let shelf = ref []
  let last = ref None

  let page (filter : Book_filter.t) request =
    let matching =
      List.filter
        (fun (book : Book.t) ->
          Option.fold ~none:true
            ~some:(fun title -> String.equal title book.title)
            filter.title)
        (List.rev !shelf)
    in
    Lwt.return
      (Kre_shared.Page.make request ~total:(List.length matching)
         (List.filteri
            (fun index _ ->
              index >= Kre_shared.Page.Request.offset request
              && index
                 < Kre_shared.Page.Request.offset request
                   + request.Kre_shared.Page.Request.size)
            matching))

  let find id =
    Lwt.return
      (List.find_opt (fun (book : Book.t) -> Book.Id.equal book.id id) !shelf)

  let create (draft : Book_draft.t) =
    let id = Option.fold ~none:Book.Id.first ~some:Book.Id.succ !last in
    let book = { Book.id; title = draft.title } in
    last := Some id;
    shelf := book :: !shelf;
    Lwt.return book

  let remove (book : Book.t) =
    shelf :=
      List.filter
        (fun (other : Book.t) -> not (Book.Id.equal other.id book.id))
        !shelf;
    Lwt.return_unit
end

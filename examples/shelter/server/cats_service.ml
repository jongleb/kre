module type S = sig
  val available : unit -> Cat.t list Lwt.t
  val find : Cat.Id.t -> Cat.t option Lwt.t

  val catalog :
    Cat_filter.t -> Kre_shared.Page.Request.t -> Cat.t Kre_shared.Page.t Lwt.t

  val owned_by : User.Id.t list -> (User.Id.t -> Cat.t list) Lwt.t
  val create : Create_cat_dto.t -> Cat.t Lwt.t
  val rename : Cat.Id.t -> Rename_dto.t -> (Cat.t, Kre.Error.t) result Lwt.t
  val adopt : Cat.Id.t -> User.Id.t -> (unit, Kre.Error.t) result Lwt.t
end

module Make (Db : Kre.Db.S with type conn = Kre_db_mariadb.Client.t) : S =
struct
  module Sql = Shelter_sql.Make (Kre_db_mariadb.Sql)
  module Cats = Cats_crud.Make (Kre_db_mariadb.Sql)

  let key id = Int64.of_int (Cat.Id.to_repr id)

  let available () =
    Db.with_conn (fun conn ->
        Cats.List.by_status conn
          ~status:(Cat.Status.to_string Available)
          Cat.of_row)

  let find id =
    Db.with_conn (fun conn -> Cats.Single.find conn ~id:(key id) Cat.of_row)

  let catalog (filter : Cat_filter.t) request =
    Db.with_conn (fun conn ->
        let status = Option.map Cat.Status.to_string filter.status
        and age_min = Option.map Int64.of_int filter.age_min
        and age_max = Option.map Int64.of_int filter.age_max in
        let%lwt cats =
          Cats.List.filter conn ~name:filter.name ~age_min ~age_max ~status
            ~limit:(Int64.of_int request.Kre_shared.Page.Request.size)
            ~offset:(Int64.of_int (Kre_shared.Page.Request.offset request))
            Cat.of_row
        in
        let%lwt total =
          Cats.filter_count conn ~name:filter.name ~age_min ~age_max ~status
        in
        Lwt.return
          (Kre_shared.Page.make request ~total:(Int64.to_int total) cats))

  let owned_by owners =
    match owners with
    | [] -> Lwt.return (fun _ -> [])
    | owners ->
        Db.with_conn (fun conn ->
            Lwt.map
              (Kre.Table.group ~key:(fun (cat : Cat.t) -> cat.owner_id))
              (Cats.List.by_owner_id_any conn
                 ~owner_id_list:
                   (List.map
                      (fun owner -> Int64.of_int (User.Id.to_repr owner))
                      owners)
                 Cat.of_row))
        |> Lwt.map (fun owned owner -> owned (Some owner))

  let create ({ name; age } : Create_cat_dto.t) =
    Db.with_conn (fun conn ->
        let%lwt inserted =
          Cats.insert conn ~name:(Cat.Name.to_repr name)
            ~age:(Int64.of_int (Cat.Age.to_repr age))
            ~status:(Cat.Status.to_string Available)
            ~owner_id:None ~version:0L
        in
        let%lwt id = Inserted.id (module Cat.Id) inserted in
        Lwt.return
          {
            Cat.id;
            name;
            age;
            status = Available;
            owner_id = None;
            version = 0;
          })

  let rename id ({ name; version } : Rename_dto.t) =
    Db.with_conn (fun conn ->
        match%lwt Cats.Single.find conn ~id:(key id) Cat.of_row with
        | None -> Lwt.return_error (Kre.Error.not_found "cat")
        | Some cat -> (
            let%lwt changed =
              Cat.for_update { cat with name; version } (Cats.update conn)
            in
            match changed.affected_rows with
            | 1L -> Lwt.return_ok { cat with name; version = version + 1 }
            | _ ->
                Lwt.return_error
                  (Kre.Error.conflict
                     "the cat changed since you read it; reload and try again")))

  let adopt id user =
    Db.with_conn (fun conn ->
        let%lwt changed =
          Sql.adopt_cat conn
            ~status:(Cat.Status.to_string Adopted)
            ~owner_id:(Some (Int64.of_int (User.Id.to_repr user)))
            ~id:(key id)
            ~available:(Cat.Status.to_string Available)
        in
        Lwt.return
          (match changed.affected_rows with
          | 1L -> Ok ()
          | _ -> Error (Kre.Error.conflict "this cat is not available")))
end

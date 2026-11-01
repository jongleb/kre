let id (module Id : Kre_shared.Id.S)
    (response : Kre_db_mariadb.Sql.execute_response) =
  Option.fold
    ~none:(Kre.Error.fail (Kre.Error.internal "insert returned no id"))
    ~some:(fun id ->
      Result.fold ~ok:Lwt.return
        ~error:(fun _ ->
          Kre.Error.fail (Kre.Error.internal "insert returned a bad id"))
        (Id.of_repr (Int64.to_int id)))
    response.insert_id

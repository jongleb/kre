let id (module Id : Forge_shared.Id.S)
    (response : Forge_db_mariadb.Sql.execute_response) =
  Option.fold
    ~none:(Forge.Error.fail (Forge.Error.internal "insert returned no id"))
    ~some:(fun id ->
      Result.fold ~ok:Lwt.return
        ~error:(fun _ ->
          Forge.Error.fail (Forge.Error.internal "insert returned a bad id"))
        (Id.of_repr (Int64.to_int id)))
    response.insert_id

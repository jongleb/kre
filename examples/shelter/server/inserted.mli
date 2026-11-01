val id :
  (module Id : Kre_shared.Id.S) ->
  Kre_db_mariadb.Sql.execute_response -> Id.t Lwt.t

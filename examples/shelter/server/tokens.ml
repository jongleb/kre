module Make (Db : Kre.Db.S with type conn = Kre_db_mariadb.Client.t) :
  Kre.Token.S =
  Kre.Token.Make (Db)

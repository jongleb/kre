module Make (Db : Kre.Db.S with type conn = Kre_db_mariadb.Client.t) :
  Kre.Job.S =
  Kre.Job.Make
    (Db)
    (struct
      let poll = 0.1
      let attempts = 3
    end)

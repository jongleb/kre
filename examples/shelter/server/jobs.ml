module Make (Db : Forge.Db.S with type conn = Forge_db_mariadb.Client.t) :
  Forge.Job.S =
  Forge.Job.Make
    (Db)
    (struct
      let poll = 0.1
      let attempts = 3
    end)

module Make (Settings : Settings.S) = struct
  include
    Forge.Db.Make
      (Forge_db_mariadb.Driver)
      (struct
        let url = Settings.database_url
        let size = 4
      end)

  let on_start () =
    with_conn (fun conn ->
        Lwt.map ignore
          (Forge.Migration.up
             (module Forge_db_mariadb.Driver)
             conn
             (Result.get_ok
                (Forge.Migration.of_files [%embed_dir "migrations"]))))

  let ping () =
    Lwt.catch
      (fun () ->
        with_conn (fun conn ->
            Lwt.map
              (fun _ -> Ok ())
              (Forge_db_mariadb.Driver.strings conn "SELECT 1")))
      (fun exn -> Lwt.return_error (Printexc.to_string exn))
  [@@health "db"]
end

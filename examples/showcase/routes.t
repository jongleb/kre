Every route of the showcase, straight from the controllers' specs.

  $ ./main.exe --emit-spec spec.json
  $ kre routes --spec spec.json
  GET     /cats                            find_all 200
  GET     /cats/:id                        find_one 200
  POST    /cats                            create 201
  DELETE  /admin/cats                      purge 204
  GET     /notes/:id                       read 200
  POST    /session/login                   login 200
  POST    /session/reset                   reset 204
  PUT     /entities/:id                    update 200
  PATCH   /entities/:id                    rename 200
  GET     /whoami                          show 200
  GET     /trace                           show 200
  GET     /audit/:id                       secret 200
  GET     /audit/slow                      slow 200
  GET     /legacy/cats                     old_cats 302
  GET     /legacy/slow                     slow 200
  GET     /legacy/fresh                    fresh 200
  GET     /legacy/gone                     gone 204
  GET     /v2/legacy/status                status 200
  GET     /legacy/plain                    plain 204
  GET     /ticks                           count 200
  GET     /files/*                         download 200
  OPTIONS /files/probe                     probe 204
  GET     /files/echo                      echo 200
  POST    /files/echo                      echo 200
  PUT     /files/echo                      echo 200
  PATCH   /files/echo                      echo 200
  DELETE  /files/echo                      echo 200
  HEAD    /files/echo                      echo 200
  OPTIONS /files/echo                      echo 200
  GET     /tenant                          whoami 200
  GET     /stats                           summary 200

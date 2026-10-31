let use : Dream.middleware =
 fun next request ->
  Dream.log "Request...";
  next request

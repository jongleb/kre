let handler : Kre.Error.handler =
 fun request error ->
  match error.code with
  | "not_found" -> Dream.html ~status:`Not_Found "<h1>Nothing here</h1>"
  | _ -> Kre.Error.to_response request error

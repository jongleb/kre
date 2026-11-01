[@@@controller "tokens"]

let issue (module Tokens : Kre.Token.S) ~(user : (User.t[@guard Auth.current]))
    ~(body : Token_request.t) : Issued_token.t Lwt.t =
  Lwt.map
    (fun (token, (issued : Kre.Token.t)) ->
      { Issued_token.id = issued.id; token; abilities = issued.abilities })
    (Tokens.issue
       ~owner:(string_of_int (User.Id.to_repr user.id))
       ~abilities:body.abilities)
[@@post] [@@status 201] [@@summary "An API token for scripts"]

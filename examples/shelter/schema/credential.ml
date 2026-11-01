type t = {
  user_id : User.Id.t; [@primary] [@column int] [@references User]
  hash : string; [@size 255]
}
[@@deriving table ~name:"credentials"]

let derive ~salt password =
  Dream.to_base64url
    (Pbkdf.pbkdf2 ~prf:`SHA256 ~password ~salt ~count:100_000 ~dk_len:32l)

let make ~user_id ~password =
  let salt = Dream.random 16 in
  {
    user_id;
    hash =
      String.concat "$"
        [ "pbkdf2-sha256"; Dream.to_base64url salt; derive ~salt password ];
  }

let verify credential ~password =
  match String.split_on_char '$' credential.hash with
  | [ "pbkdf2-sha256"; salt; key ] ->
      Option.bind (Dream.from_base64url salt) (fun salt ->
          match Eqaf.equal key (derive ~salt password) with
          | true -> Some credential.user_id
          | false -> None)
  | _ -> None

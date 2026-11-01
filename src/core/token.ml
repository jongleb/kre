let table =
  Table.make ~name:"kre_tokens"
    [
      Table.column ~role:Primary "id" (Text (Some 26)) Not_null;
      Table.column ~role:Index "owner" (Text (Some 128)) Not_null;
      Table.column ~role:Unique "hash" (Text (Some 64)) Not_null;
      Table.column "abilities" (Text None) Not_null;
      Table.column "created" Double Not_null;
    ]

type t = { id : string; owner : string; abilities : string list }

module type S = sig
  val issue : owner:string -> abilities:string list -> (string * t) Lwt.t
  val tokens : owner:string -> t list Lwt.t
  val revoke : string -> unit Lwt.t
  val current : t Guard.t
  val ability : string -> t Guard.t
end

module Make (Db : Db.S) = struct
  let hash secret =
    Digestif.SHA256.to_hex (Digestif.SHA256.digest_string secret)

  let read rows =
    List.filter_map
      (function
        | [ Some id; Some owner; Some abilities ] ->
            Some
              {
                id;
                owner;
                abilities =
                  List.filter
                    (fun ability -> not (String.equal ability ""))
                    (String.split_on_char ' ' abilities);
              }
        | _ -> None)
      rows

  let issue ~owner ~abilities =
    let secret = Dream.to_base64url (Dream.random 32) in
    let token = { id = Ulid.next (); owner; abilities } in
    Lwt.map
      (fun _ -> (secret, token))
      (Db.query
         "INSERT INTO kre_tokens (id, owner, hash, abilities, created) VALUES \
          (?, ?, ?, ?, ?)"
         [
           Some token.id;
           Some owner;
           Some (hash secret);
           Some (String.concat " " abilities);
           Some (Printf.sprintf "%.17g" (Unix.gettimeofday ()));
         ])

  let tokens ~owner =
    Lwt.map read
      (Db.query
         "SELECT id, owner, abilities FROM kre_tokens WHERE owner = ? ORDER BY \
          id"
         [ Some owner ])

  let revoke id =
    Lwt.map ignore (Db.query "DELETE FROM kre_tokens WHERE id = ?" [ Some id ])

  let current request =
    match Dream.header request "Authorization" with
    | Some authorization when String.starts_with ~prefix:"Bearer " authorization
      ->
        let secret =
          String.sub authorization 7 (String.length authorization - 7)
        in
        Lwt.map
          (fun rows ->
            match read rows with
            | token :: _ -> Ok token
            | [] -> Error (Error.unauthorized "unknown or revoked token"))
          (Db.query "SELECT id, owner, abilities FROM kre_tokens WHERE hash = ?"
             [ Some (hash secret) ])
    | Some _ | None ->
        Lwt.return_error (Error.unauthorized "missing bearer token")

  let ability wanted =
    Guard.check
      (fun token ->
        match
          List.find_opt
            (fun ability ->
              String.equal ability wanted || String.equal ability "*")
            token.abilities
        with
        | Some _ -> Ok token
        | None ->
            Error
              (Error.forbidden
                 (Printf.sprintf "the token does not allow %s" wanted)))
      current
end

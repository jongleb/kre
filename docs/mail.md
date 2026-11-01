# Mail

In Kre an email is a value `Kre.Mail.t`, delivery is a provider `Kre.Mail.S`.

```ocaml
Kre.Mail.make ~from ~to_ ?cc ~subject ~text ?html ()
```
```mdx-error
Line 1, characters 1-4:
Error: Unbound module Kre
```

- Addresses are `Kre_shared.Refined.Email.t`, and a recipient is required: an email without a recipient cannot be built.
- `Kre.Mail.render` prints an RFC 5322 message: with `html` it is `multipart/alternative`; a non-ASCII subject is encoded (`=?UTF-8?B?…?=`).
- `Kre.Mail.Smtp (Config)` sends over SMTP (`EHLO`, `MAIL FROM`, `RCPT TO`, `DATA` with dot-stuffing). No TLS: for a local relay or Mailpit; STARTTLS comes later.
- `Kre.Mail.Outbox ()` keeps emails in memory and serves the page `/__kre/mail` with their contents: for dev and tests.

In `examples/shelter` the mail provider is the outbox:

<!-- $MDX file=../examples/shelter/server/mail.ml -->
```ocaml
[@@@injectable Kre.Mail.S]

include Kre.Mail.Outbox ()
```

The adoption email is sent by a queue handler that `[%wire]` gave `Mail`:

<!-- $MDX file=../examples/shelter/server/mailer.ml -->
```ocaml
module type S = sig
  val congratulate : Adoption.t -> (unit, string) result Lwt.t
end

module Make (Mail : Kre.Mail.S) : S = struct
  let congratulate (adoption : Adoption.t) =
    Mail.send
      (Kre.Mail.make
         ~from:
           (Kre_shared.Validation.ok_exn
              (Kre_shared.Refined.Email.of_repr "shelter@shelter.test"))
         ~to_:
           (Kre_shared.Validation.ok_exn
              (Kre_shared.Refined.Email.of_repr "staff@shelter.test"))
         ~subject:"A cat found a home"
         ~text:
           (Printf.sprintf "user %s adopted cat %s"
              (User.Id.to_string adoption.user_id)
              (Cat.Id.to_string adoption.cat_id))
         ())
  [@@job Queues.congratulate]
end
```

Replacing the outbox with SMTP is a different `Kre.Mail.S` provider (for example, `module Make (Settings : Settings.S) = Kre.Mail.Smtp (…)`) with `[@@@primary]`; the `Mailer` code does not change.

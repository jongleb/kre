# Mail

Rails: ActionMailer и превью писем. Symfony: Mailer. Nest: `@nestjs-modules/mailer`. Forge: письмо — значение `Forge.Mail.t`, доставка — провайдер `Forge.Mail.S`.

```ocaml
Forge.Mail.make ~from ~to_ ?cc ~subject ~text ?html ()
```
```mdx-error
Line 1, characters 1-6:
Error: Unbound module Forge
```

- Адреса — `Forge_shared.Refined.Email.t`, получатель обязателен: письмо без адресата не построить.
- `Forge.Mail.render` печатает письмо RFC 5322: с `html` — `multipart/alternative`, тема не в ASCII кодируется (`=?UTF-8?B?…?=`).
- `Forge.Mail.Smtp (Config)` — отправка по SMTP (`EHLO`, `MAIL FROM`, `RCPT TO`, `DATA` с dot-stuffing). Без TLS: для локального relay или Mailpit; STARTTLS — позже.
- `Forge.Mail.Outbox ()` — письма в памяти и страница `/__forge/mail` с их содержимым, как превью ActionMailer: для dev и тестов.

В `examples/shelter` провайдер почты — outbox:

<!-- $MDX file=../examples/shelter/server/mail.ml -->
```ocaml
[@@@injectable Forge.Mail.S]

include Forge.Mail.Outbox ()
```

А письмо об усыновлении шлёт обработчик очереди, которому `[%wire]` передал `Mail`:

<!-- $MDX file=../examples/shelter/server/mailer.ml -->
```ocaml
module type S = sig
  val congratulate : Adoption.t -> (unit, string) result Lwt.t
end

module Make (Mail : Forge.Mail.S) : S = struct
  let congratulate (adoption : Adoption.t) =
    Mail.send
      (Forge.Mail.make
         ~from:
           (Forge_shared.Validation.ok_exn
              (Forge_shared.Refined.Email.of_repr "shelter@shelter.test"))
         ~to_:
           (Forge_shared.Validation.ok_exn
              (Forge_shared.Refined.Email.of_repr "staff@shelter.test"))
         ~subject:"A cat found a home"
         ~text:
           (Printf.sprintf "user %s adopted cat %s"
              (User.Id.to_string adoption.user_id)
              (Cat.Id.to_string adoption.cat_id))
         ())
  [@@job Queues.congratulate]
end
```

Заменить outbox на SMTP — другой провайдер `Forge.Mail.S` (например, `module Make (Settings : Settings.S) = Forge.Mail.Smtp (…)`) с `[@@@primary]`; код `Mailer` не меняется.

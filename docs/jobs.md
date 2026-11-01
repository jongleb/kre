# Queues и фоновые задачи

Nest: `@nestjs/bullmq` (Redis). Rails: ActiveJob + Solid Queue. Symfony: Messenger. IHP: Jobs. Spring: `@Async`. В Kre очередь живёт в той же базе, что и данные (как Solid Queue и IHP): таблица `kre_jobs`, захват `FOR UPDATE SKIP LOCKED`, Redis не нужен.

Очередь — типизированное значение: имя и dto полезной нагрузки.

<!-- $MDX file=../examples/shelter/server/queues.ml -->
```ocaml
let congratulate : Adoption.t Kre.Job.queue =
  Kre.Job.queue "congratulate" (module Adoption)
```

Исполнитель — провайдер `Kre.Job.Make (Db) (Config)`; `[%wire]` сам запускает его воркер в `on_start` и останавливает в `on_shutdown`.

<!-- $MDX file=../examples/shelter/server/jobs.ml -->
```ocaml
module Make (Db : Kre.Db.S with type conn = Kre_db_mariadb.Client.t) :
  Kre.Job.S =
  Kre.Job.Make
    (Db)
    (struct
      let poll = 0.1
      let attempts = 3
    end)
```

Обработчик — функция провайдера с `[@@job очередь]`, её регистрирует `[%wire]`:

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

Постановка — `Jobs.enqueue очередь значение` из любого сервиса, которому дали `(Jobs : Kre.Job.S)`. Запрос идёт через `Db`, поэтому внутри транзакции задача пишется в неё же: откат транзакции убирает и задачу (transactional outbox без отдельного кода). В `examples/shelter` усыновление ставит письмо; третье усыновление откатывается — письма нет.

- Тип нагрузки проверяется при постановке (компилятор) и при выполнении (`Kre_shared.Json.parse`).
- `Ok ()` — задача удаляется; `Error msg` или исключение — повтор через 2, 4, 8… секунд, `last_error` сохраняется; после `attempts` попыток — `status = 'dead'`.
- Задача, чей воркер упал, возвращается в очередь через 5 минут (`locked_until`).
- `Jobs.drain ()` выполняет всё, что пора, и возвращает число задач — для тестов и скриптов.
- Таблица — `Kre.Job.table`: `schema.exe` печатает её миграцию так же, как миграции приложения (`examples/shelter/server/migrations/0002_jobs.sql`).

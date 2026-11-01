# Queues and background jobs

In Kre the queue lives in the same database as the data: table `kre_jobs`, claiming with `FOR UPDATE SKIP LOCKED`, no separate broker needed.

A queue is a typed value: a name and the payload dto.

<!-- $MDX file=../examples/shelter/server/queues.ml -->
```ocaml
let congratulate : Adoption.t Kre.Job.queue =
  Kre.Job.queue "congratulate" (module Adoption)
```

The executor is the provider `Kre.Job.Make (Db) (Config)`; `[%wire]` starts its worker in `on_start` and stops it in `on_shutdown`.

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

A handler is a provider function with `[@@job queue]`; `[%wire]` registers it:

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

Enqueueing is `Jobs.enqueue queue value` from any service that was given `(Jobs : Kre.Job.S)`. The query goes through `Db`, so inside a transaction the job is written into that transaction: rolling back the transaction removes the job too (a transactional outbox with no extra code). In `examples/shelter` an adoption enqueues an email; the third adoption is rolled back, and there is no email.

- The payload type is checked at enqueue time (by the compiler) and at run time (`Kre_shared.Json.parse`).
- `Ok ()`: the job is deleted; `Error msg` or an exception: retry after 2, 4, 8… seconds, `last_error` is saved; after `attempts` attempts: `status = 'dead'`.
- A job whose worker crashed returns to the queue after 5 minutes (`locked_until`).
- `Jobs.drain ()` runs everything that is due and returns the number of jobs; for tests and scripts.
- The table is `Kre.Job.table`: `schema.exe` prints its migration the same way as the application's migrations (`examples/shelter/server/migrations/0002_jobs.sql`).

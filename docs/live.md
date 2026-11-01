# Live loaders

With a live loader, a page re-fetches its data when someone has changed the tables it reads from. The application has no subscription code.

1. The handler declares the tables it depends on:

<!-- $MDX skip -->
```ocaml
let find_all (module Cats : Cats_service.S)
    ~(search : (Cat_search.t[@search])) () : Cat.t list Lwt.t = …
[@@get] [@@summary "List cats"] [@@live [ "cats" ]]
```

   `[@@live]` is allowed only on GET and only with strings. Otherwise it is a build error.

2. The server publishes changes by itself:
   - the driver (`Kre_db_mariadb.Sql`) sees the SQL of every query: `INSERT`/`UPDATE`/`DELETE` publish their table;
   - inside `Db.transaction` and `[@@transactional]`, changes wait for the commit and are dropped after a rollback;
   - a store without SQL calls `Kre.Live.publish [ "cats" ]`.

   No database triggers are needed, so this works on MariaDB too.

3. Channel: `Kre.Live.controller` is `GET /__kre/live?table=cats`, server-sent events, one event per change. It is mounted next to the other controllers.

4. Client: `kre client` puts the tables of every live route into `Cats_client.Live`; the router reruns the loader on an event:

<!-- $MDX skip -->
```ocaml
Kre_client.Router.child ~live:Cats_client.Live.find_all root
  ~path:[%path "/cats"] ~search:Cat_search.codec
  ~loader:(fun () search -> Cats_client.find_all ~search)
  ~component:Pages.index
```

   Outside the router: `Kre_client.Live.watch [ "cats" ] (fun table -> …)`, which returns an unsubscribe function.

## List check

Forgetting a table in `[@@live]` means silently losing updates. So a route with `[@@live]` records which tables its SQL queries read (`SELECT … FROM/JOIN`):
- with `KRE_ENV=test` a missing table gives 500 with the text `/cats reads users; add it to [@@live]`, and the e2e test fails;
- with `dev` (the default) it is a warning in the log;
- other profiles have no check.

Limits: one process, an in-memory bus; tables are found by the SQL text (`FROM a, b` sees only `a`); changes made outside the application are not visible.

Tested: `test/core` (bus, transactions, list check), `examples/cats/db/test` (commit and rollback on MariaDB), `examples/cats/client_js` (node receives `cats` over EventSource after another client's request).

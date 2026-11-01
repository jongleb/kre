# Profiler

Symfony: Web Profiler. Rails: SQL in the development log and Bullet for N+1. Spring: `/actuator/httpexchanges`. Kre: `Kre.Profiler`, only with `KRE_ENV=dev` (or when it is unset); in other profiles the middleware does nothing and the pages answer 404.

```ocaml
Kre.App.run
  ~middleware:[ Dream.logger; Kre.Profiler.middleware; actuator.metrics ]
  (actuator.controller :: Kre.Live.controller :: Kre.Profiler.controller
   :: app.controllers)
```
```mdx-error
Line 1, characters 1-4:
Error: Unbound module Kre
```

- `/__kre/profiler`: the last 50 requests: method, path, status, time and all SQL in execution order.
- `/__kre/profiler.json`: the same in JSON.
- The same query three or more times within one request gets an `N+1` mark (like Bullet): usually this is a loop over a service that should become one `JOIN` or a `by_<column>` from `Table.crud`.

SQL is recorded by the drivers (`kre-db-mariadb`, `kre-db-postgresql`) and `Db.query`, so both sqlgg queries and job queue queries are visible. Each HTTP request collects its own list in an Lwt key, so concurrent requests do not mix.

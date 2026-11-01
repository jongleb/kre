# Profiler

Symfony: Web Profiler. Rails: SQL в логе разработки и Bullet для N+1. Spring: `/actuator/httpexchanges`. Kre: `Kre.Profiler`, только при `KRE_ENV=dev` (или когда он не задан); в остальных профилях middleware ничего не делает, а страницы отвечают 404.

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

- `/__kre/profiler` — последние 50 запросов: метод, путь, статус, время и весь SQL в порядке выполнения.
- `/__kre/profiler.json` — то же в JSON.
- Один и тот же запрос три и больше раз за запрос — пометка `N+1` (как Bullet): обычно это цикл по сервису, который просится в один `JOIN` или `by_<column>` из `Table.crud`.

SQL пишут драйверы (`kre-db-mariadb`, `kre-db-postgresql`) и `Db.query`, поэтому видны и запросы sqlgg, и запросы очереди задач. Каждый запрос HTTP собирает свой список в ключе Lwt, так что параллельные запросы не смешиваются.

# Caching

Nest: `CacheInterceptor`, `@CacheKey`, `@CacheTTL`. Spring: `@Cacheable`, `@CacheEvict`. Kre — два уровня.

**Ответ целиком** — `[@@cache секунды]` на GET-хендлере: ответ 200 хранится в памяти по URL, повтор отдаётся без вызова хендлера (`X-Cache: hit`). Потоки SSE не кэшируются; `[@@cache]` на не-GET — ошибка компиляции.

<!-- $MDX file=examples/stats_controller.ml -->
```ocaml
[@@@controller "stats"]

let computed = ref 0

let summary () : string Lwt.t =
  incr computed;
  Lwt.return (Printf.sprintf "computed %d times" !computed)
[@@get] [@@cache 60.0]
```

**Функция сервиса** — `Kre.Cache.memoize ~ttl f` возвращает `{ find; evict; clear }`: `find` — `@Cacheable`, `evict key` и `clear ()` — `@CacheEvict`. Ключ и значение типизированы, поэтому это функция, а не аннотация:

<!-- $MDX skip -->
```ocaml
let prices = Kre.Cache.memoize ~ttl:300. (fun sku -> Catalog.price sku)
let price sku = prices.find sku
let changed sku = prices.evict sku
```

Кэш живёт в памяти процесса; общий кэш на несколько процессов (Redis) — фаза 3.

**HTTP-кэш клиента** — `[@@etag]` на GET-хендлере, как `fresh_when` в Rails и `ShallowEtagHeaderFilter` в Spring. Ответ 200 получает `ETag` (хеш тела); запрос с тем же `If-None-Match` получает `304 Not Modified` без тела. Хендлер выполняется, экономится трафик и разбор на клиенте. На весь сервер — `Kre.Etag.middleware` в `~middleware`; потоки SSE он пропускает.

<!-- $MDX skip -->
```ocaml
let find_one (module Cats : Cats_service.S) ~(id : Cat.Id.t) : (Cat.t, Kre.Error.t) result Lwt.t = …
[@@get ":id"] [@@etag]
```

# Caching

Nest: `CacheInterceptor`, `@CacheKey`, `@CacheTTL`. Spring: `@Cacheable`, `@CacheEvict`. Forge — два уровня.

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

**Функция сервиса** — `Forge.Cache.memoize ~ttl f` возвращает `{ find; evict; clear }`: `find` — `@Cacheable`, `evict key` и `clear ()` — `@CacheEvict`. Ключ и значение типизированы, поэтому это функция, а не аннотация:

<!-- $MDX skip -->
```ocaml
let prices = Forge.Cache.memoize ~ttl:300. (fun sku -> Catalog.price sku)
let price sku = prices.find sku
let changed sku = prices.evict sku
```

Кэш живёт в памяти процесса; общий кэш на несколько процессов (Redis) — фаза 3.

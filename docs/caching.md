# Caching

Nest: `CacheInterceptor`, `@CacheKey`, `@CacheTTL`. Spring: `@Cacheable`, `@CacheEvict`. Kre has two levels.

**Whole response**: `[@@cache seconds]` on a GET handler: a 200 response is stored in memory by URL, and a repeat is served without calling the handler (`X-Cache: hit`). SSE streams are not cached; `[@@cache]` on a non-GET is a compile error.

<!-- $MDX file=examples/stats_controller.ml -->
```ocaml
[@@@controller "stats"]

let computed = ref 0

let summary () : string Lwt.t =
  incr computed;
  Lwt.return (Printf.sprintf "computed %d times" !computed)
[@@get] [@@cache 60.0]
```

**Service function**: `Kre.Cache.memoize ~ttl f` returns `{ find; evict; clear }`: `find` is `@Cacheable`, `evict key` and `clear ()` are `@CacheEvict`. The key and value are typed, so this is a function, not an annotation:

<!-- $MDX skip -->
```ocaml
let prices = Kre.Cache.memoize ~ttl:300. (fun sku -> Catalog.price sku)
let price sku = prices.find sku
let changed sku = prices.evict sku
```

The cache lives in process memory; a cache shared across several processes (Redis) is phase 3.

**Client HTTP cache**: `[@@etag]` on a GET handler, like `fresh_when` in Rails and `ShallowEtagHeaderFilter` in Spring. A 200 response gets an `ETag` (a hash of the body); a request with the same `If-None-Match` gets `304 Not Modified` without a body. The handler still runs; what is saved is traffic and parsing on the client. For the whole server: `Kre.Etag.middleware` in `~middleware`; it skips SSE streams.

<!-- $MDX skip -->
```ocaml
let find_one (module Cats : Cats_service.S) ~(id : Cat.Id.t) : (Cat.t, Kre.Error.t) result Lwt.t = …
[@@get ":id"] [@@etag]
```

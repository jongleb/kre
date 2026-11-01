<script setup>
const generated = [
  { title: 'You write', sub: 'Functions with typed parameters and a verb attribute', code: 'let find_one … [@@get ":id"]', tone: 'ember' },
  { title: 'Paths', sub: 'A typed route per handler, usable from code', code: 'Paths.find_one ()', tone: 'amber' },
  { title: 'spec', sub: 'The contract: params, bodies, results', code: 'val spec : Kre.Spec.t', tone: 'sky' },
  { title: 'register', sub: 'Takes the dependencies, returns a controller', code: 'register (module Cats)', tone: 'mint' }
]

const classify = [
  { title: '(module M : S)', sub: 'A dependency: becomes a parameter of register', tone: 'violet' },
  { title: '~id matches :id', sub: 'Path segment, parsed by its type', tone: 'sky' },
  { title: '~body', sub: 'JSON body through the DTO decoder', tone: 'amber' },
  { title: '[@guard] / [@from]', sub: 'A value computed from the request', tone: 'magma' },
  { title: 'anything else', sub: 'Query parameter; option and list allowed', tone: 'mint' }
]
</script>

# Controllers

<p class="lead">A controller is a file of plain functions. Each handler's labelled arguments say where values come from, its module arguments say what it depends on, and its return type decides the response. <code>kre-ppx</code> reads all of that at compile time and writes the routing, parsing and serialisation for you.</p>

<Flow :steps="generated" caption="What kre-ppx adds to every controller file" />

## A first controller

This is the controller from the small `cats` example:

<<< @/../examples/cats/server/cats_controller.ml

- `[@@@controller "cats"]` must be the first item of the file. Every route lives under `/cats`. An empty string is allowed.
- `[@@@use [ … ]]` applies Dream middleware to every route in the file.
- Each handler is a `let` with a verb attribute and a **mandatory return type annotation**.
- The file stays as you wrote it. The ppx appends `Paths`, `spec` and `register`, so you can still call `find_one` directly in a test.

The application registers it with its dependency:

```ocaml
Kre.App.run [ Cats_controller.register (module Cats_service) ]
```

Forget the module, or pass one with the wrong signature, and the program does not compile. In a real app `[%wire]` writes that call for you — see [Dependency injection](/guide/dependency-injection).

Generated paths are ordinary values you can use anywhere:

```ocaml
Routes.sprintf (Cats_controller.Paths.find_one ()) 42 = "/cats/42"
```

## Verbs and paths

| Attribute | Method |
| --- | --- |
| `[@@get]`, `[@@get ":id"]` | GET; HEAD falls back to it with no body |
| `[@@post]`, `[@@put]`, `[@@patch]`, `[@@delete]` | the usual |
| `[@@head]`, `[@@options]` | explicit HEAD and OPTIONS |
| `[@@all "echo"]` | every method |
| `[@@get "*"]` | a wildcard; the rest of the path goes to a `[@wildcard]` parameter |

The path is relative to the controller prefix. A segment `:name` must have a labelled parameter of the same name, and the parameter's type parses the segment. A segment that does not parse is not a match, so `/cats/abc` with `~(id : int)` is a plain 404.

<<< @/../docs/examples/files_controller.ml

## Where each parameter comes from

The ppx sees only syntax, never types, so it classifies parameters by their shape and attributes, in this order:

<Flow :steps="classify" caption="How a handler parameter is classified" />

1. **Module parameter** `(module Cats : Cats_service.S)` — a dependency. Module parameters of all handlers are merged by name and become the parameters of `register`, in order of first appearance. One name with two signatures is an error.
2. **Path** — the label appears as `:label` in the full path. A type annotation is required; it cannot be optional.
3. **Body** — the label is `body`. JSON goes through `T.of_json`: not JSON is `400`, a failed parse or rule is `422` with every field error.
4. **Guard** — the parameter carries `[@guard e]` or its synonym `[@from e]`, where `e : 'a Kre.Guard.t`. It runs before the body, an `Error` stops the request, and it never appears in the spec or the client.
5. **Query** — everything else that is labelled. `~(x : t)` is required (missing is `400`), `?(x : t option)` is optional, `?(x : t = d)` has a default, and `~(x : t list)` repeats: `?x=a&x=b`.
6. **Positional** — `(req : Dream.request)`, a positional `[@from e]`, or the final `()`.

A parameter type is `int`, `int64`, `float`, `bool`, `string` or `T.t` where `T` is a scalar (`Kre_shared.Scalar.S`). Refined types like `Cat.Name.t` and ids like `Cat.Id.t` are scalars, so a bad value never reaches your code.

### Attributes on parameters

When the default rules are not enough, an attribute on the parameter's type names the source. The type still decides how the value is parsed and whether it is required.

| You want | Kre |
| --- | --- |
| a differently named path segment | `[@param "id"]` |
| a differently named query key | `[@query "page-size"]` |
| the whole query string as a record | `[@search]` |
| one field of the body | `[@body "name"]` |
| a header | `[@header "X-Client-Name"]` |
| a cookie | `[@cookie "theme"]`, `[@signed_cookie "sid"]` |
| a session value | `[@session "user_id"]` |
| client address, host | `[@ip]`, `[@host]`, `[@host_param "account"]` |
| an uploaded file, a form field | `[@file "avatar"]`, `[@files "photos"]`, `[@form "title"]` |
| the entity behind a path id | `[@load Cats.find]` |
| anything computed from the request | `[@from guard]` |
| the raw request | `(req : Dream.request)` |

A handler that uses most of them:

<<< @/../docs/examples/entities_controller.ml

Headers and cookies are part of the spec, so they show up in OpenAPI and headers become arguments of the generated client.

### Your own decorators

A custom parameter decorator is any value of type `'a Kre.Guard.t`, that is `Dream.request -> ('a, Kre.Error.t) result Lwt.t`:

<<< @/../docs/examples/decorators.ml

<<< @/../docs/examples/whoami_controller.ml

### Search records and loaded entities

`[@search]` reads the whole query string into a record that derives `search` and `dto`. The same record parses page URLs in the [client router](/client/client-router), so the server and the browser agree on `?limit=10&breed=siamese`:

<<< @/../examples/cats/shared/cat_search.ml

`[@load f]` loads the entity behind a path id. With `[@@get ":cat"]`, the segment is parsed as `Cat.Id.t`, `f` is called with it and must return `Cat.t option Lwt.t`; `None` is a 404. Your handler and any `[@@authorize]` check receive the loaded record, while the client and OpenAPI see an ordinary id. The shelter's cats controller uses both:

<<< @/../examples/shelter/server/cats_controller.ml{7-10,12-16}

## Return types decide the response

| Return type | Response | Default status |
| --- | --- | --- |
| `unit Lwt.t` | empty body | `204` |
| `string Lwt.t` | `text/plain` | `200` |
| `T.t Lwt.t` | `T.to_json`, `application/json` | `200` |
| `T.t list Lwt.t` | a JSON array | `200` |
| `T.t option Lwt.t` | JSON, or `404` on `None` | `200` |
| `T.t M.t Lwt.t` | a container, e.g. `Cat.t Kre_shared.Page.t` through `Kre_shared.Page.Make (Cat)` | `200` |
| `(τ, Kre.Error.t) result Lwt.t` | as `τ`; `Error e` becomes Problem Details | `200` / `e.status` |
| `Dream.response Lwt.t` | as is; you are in charge | yours |
| `T.t Lwt_stream.t Lwt.t` with `[@@sse]` | `text/event-stream`, one `data:` event per element | `200` |

The type is also what goes into the spec, so the OpenAPI schema and the generated client's result type always match what the handler really returns. A container of your own is a module with a type `'a t` and a `Make (J : Kre_shared.Json.S)` functor, like `Kre_shared.Page`.

::: warning The return type is not optional
The ppx cannot see inferred types, so every handler needs an annotation:

```text
Error: handler f: missing return type annotation; add one before =, e.g. : Cat.t Lwt.t
```

A path segment without a parameter is caught too:

```text
Error: path segment :id has no parameter; add ~(id : int) to the handler
```

Each ppx error points at the offending node and says what to do. The full list is in `test/ppx/errors.t`.
:::

## Status, headers, redirects and more

| Attribute | Effect |
| --- | --- |
| `[@@status 201]` | success status (100–599, checked at compile time) |
| `[@@header "Cache-Control", "no-store"]` | a header on success; repeatable |
| `[@@redirect "/cats"]` | redirect (302 by default); the handler returns `unit Lwt.t` |
| `[@@timeout 5.0]` | `504` if the handler takes longer |
| `[@@version 2]`, `[@@@version 2]` | a `/v2` prefix for one handler or the whole file |
| `[@@@host ":account.example.com"]` | the controller answers only on matching hosts |
| `[@@@error_handler h]`, `[@@error_handler h]` | an exception filter for the file or one handler |
| `[@@summary "…"]`, `[@@description "…"]` | OpenAPI text |

<<< @/../docs/examples/legacy_controller.ml

Cross-cutting behaviour is also an attribute: `[@@guards]` and `[@@authorize]` (see [Guards & auth](/guide/guards-auth)), `[@@transactional]` (see [Transactions](/data/transactions)), `[@@live]` (see [Live loaders](/data/live)), `[@@etag]`, `[@@cache]`, `[@@intercept]` and `[@@retry]` (see [Errors & interceptors](/guide/errors)).

## CRUD in one item: `[%%resource]`

A controller that only lists, shows, creates and deletes one kind of record can say so instead of writing the four handlers:

<<< @/../docs/examples/books_controller.ml

`service` is the dependency, written as a handler would take it; `entity` is the module of the record type; `actions` lists the routes to generate:

| Action | Route | Calls |
| --- | --- | --- |
| `Index` | `GET /books?page=&size=` | `Books.page request` |
| `Index Book_filter` | `GET /books?title=…&page=&size=` | `Books.page filter request` |
| `Show` | `GET /books/:book` | `Books.find id`; 404 when it returns `None` |
| `Create Book_draft` | `POST /books` → 201 | `Books.create body` |
| `Remove` | `DELETE /books/:book` → 204 | `Books.find id`, then `Books.remove book` |

The service is an ordinary provider whose signature has those functions:

<<< @/../docs/examples/books.ml{1-8}

The generated handlers are plain code: `Show` is `~(book : (Book.t [@load Books.find]))`, `Index Book_filter` reads the filter with `[@search]`, and the body is validated like any other. Everything else in the file still works: add your own handlers next to `[%%resource]`, or attributes on the controller such as `[@@@guards]`. `[%wire]` reads the resource and passes the service.

## Server-sent events

Return a stream and add `[@@sse]`. Each element is sent as `data: <json>`:

<<< @/../docs/examples/ticks_controller.ml

A stream without `[@@sse]`, or `[@@sse]` without a stream, is a compile error.

## WebSocket gateways

A gateway is a controller for WebSocket events. Frames are `{"event": "say", "data": …}`:

<<< @/../docs/examples/chat_gateway.ml

- `[@@@gateway "chat"]` serves a WebSocket at `/chat`.
- `[@@subscribe "say"]` handles one event. `~(body : T.t)` is the data, `(socket : Kre.Gateway.socket)` is the connected client and `(module M : S)` parameters are dependencies, as in controllers.
- A `T.t Lwt.t` result goes back to the sender under the same event; `unit Lwt.t` sends nothing; `Kre.Gateway.broadcast` reaches every client.
- Parse and handler errors come back as an `error` event carrying Problem Details.

The ppx generates `gateway`, which tests can drive with `Kre.Gateway.connect`, and `register`, which plugs it into `Kre.App` like any controller.

---
layout: home

hero:
  name: Kre
  text: Typed full-stack OCaml
  tagline: The structure of Nest, the power of Spring, the speed of Rails — with mistakes caught by the compiler instead of your users.
  image:
    src: /logo.svg
    alt: Kre
  actions:
    - theme: brand
      text: Get started
      link: /guide/getting-started
    - theme: alt
      text: Why Kre
      link: /guide/introduction
    - theme: alt
      text: Tour a real app
      link: /reference/shelter

features:
  - icon: 🧬
    title: One type, every layer
    details: A record with [@@deriving table, dto] becomes the SQL table, checked queries, JSON validation, OpenAPI and the browser client.
  - icon: 🧩
    title: Dependency injection at build time
    details: "[%wire] reads your modules, orders the functors and fails the build on a missing or ambiguous provider. No runtime container."
  - icon: 🛡️
    title: Decorators as ppx
    details: Guards, [@@authorize], [@@transactional], [@load], [@search], [@@retry], [@@etag] — the Nest and Spring vocabulary, rewritten at compile time.
  - icon: ⚡
    title: Live pages
    details: Mark a GET with [@@live ["cats"]] and every page reading it reloads after a commit. No subscription code.
  - icon: 🗄️
    title: SQL you can trust
    details: sqlgg types every query against the schema your types printed. MariaDB and PostgreSQL, CRUD, finders, pages, versions.
  - icon: 🌐
    title: The same code in the browser
    details: Shared types compile to native and to JavaScript with Melange. Pages are .mlx, routes are typed, clients are generated.
---

<div class="home-section">
  <h2 class="home-title">Write the type once. <span>Get six things for free.</span></h2>
  <p class="home-sub">Kre is built around a single idea: the type you write in <code>shared/</code> is the source of truth. The database, the wire format, the documentation and the frontend are all derived from it — so they cannot drift apart.</p>
  <TypeFanout />
</div>

<div class="home-section">
  <h2 class="home-title">Mistakes move <span>left.</span></h2>
  <p class="home-sub">Every framework catches some errors early. Kre pushes as many as it can into the compiler and the test suite, where they cost minutes instead of incidents.</p>
  <CompileVsRuntime />
</div>

<div class="home-section">
  <h2 class="home-title">The best ideas from <span>five ecosystems.</span></h2>
  <p class="home-sub">Nothing here is invented for its own sake. Each feature is a pattern that proved itself elsewhere, rebuilt from functions, modules, functors and ppx — no classes, no reflection, no proxies.</p>
  <Borrowed />
</div>

<div class="home-section">
  <h2 class="home-title">What a request <span>goes through.</span></h2>
  <p class="home-sub">Every stage is declared next to the handler and generated at compile time. Hover a stage to see what it does and how it fails.</p>
  <RequestPipeline />
</div>

<div class="home-section" style="padding-bottom: 80px">
  <h2 class="home-title">By the <span>numbers.</span></h2>
  <StatGrid :stats="[
    { value: '0', label: 'runtime containers', note: 'DI is resolved by the compiler' },
    { value: '1', label: 'type per entity', note: 'table, JSON, OpenAPI, client' },
    { value: '2', label: 'databases', note: 'MariaDB and PostgreSQL' },
    { value: '16', label: 'borrowed patterns', note: 'from Nest, Spring, Rails, Symfony, IHP' }
  ]" />
</div>

<script setup lang="ts">
import TypeFanout from './TypeFanout.vue'
import RequestPipeline from './RequestPipeline.vue'
import CompileVsRuntime from './CompileVsRuntime.vue'
import Layers from './Layers.vue'
import Capabilities from './Capabilities.vue'
</script>

<template>
<div class="home">

<section class="hero">
  <div>
    <span class="eyebrow"><i></i>A typed full-stack framework for OCaml</span>
    <h1 class="title">One type.<br><span>Every layer.</span></h1>
    <p class="sub">Write a record once. kre turns it into the database table, the queries, the JSON contract, the API document and the browser client — and the compiler checks every seam between them.</p>
    <div class="actions">
      <a class="primary" href="/guide/getting-started">Get started</a>
      <a href="/reference/shelter">Tour a real app</a>
      <a href="/guide/getting-started"><code>kre new demo</code></a>
    </div>
  </div>
  <div class="stage">
  <div class="window">
    <div class="bar"><i></i><i></i><i></i><span>server/cats_controller.ml</span></div>
<pre><span class="attr">[@@@controller "cats"]</span>

<span class="kw">let</span> find_one (<span class="kw">module</span> <span class="ty">Cats</span> : <span class="ty">Cats_service</span>.S)
    ~(cat : (<span class="ty">Cat</span>.t <span class="attr">[@load Cats.find]</span>)) : <span class="ty">Cat</span>.t <span class="ty">Lwt</span>.t =
  <span class="ty">Lwt</span>.return cat
<span class="attr">[@@get ":cat"]</span> <span class="attr">[@@live [ "cats" ]]</span>

<span class="kw">let</span> create (<span class="kw">module</span> <span class="ty">Cats</span> : <span class="ty">Cats_service</span>.S)
    ~admin:(_ : (<span class="ty">Auth.Admin</span>.t <span class="attr">[@guard Auth.admin]</span>))
    ~(body : <span class="ty">Create_cat_dto</span>.t) : <span class="ty">Cat</span>.t <span class="ty">Lwt</span>.t =
  <span class="ty">Cats</span>.create body
<span class="attr">[@@post]</span> <span class="attr">[@@status 201]</span>

<span class="kw">let</span> rename (<span class="kw">module</span> <span class="ty">Cats</span> : <span class="ty">Cats_service</span>.S)
    ~user:(_ : (<span class="ty">User</span>.t <span class="attr">[@guard Auth.current]</span>))
    ~(cat : (<span class="ty">Cat</span>.t <span class="attr">[@load Cats.find]</span>)) ~(body : <span class="ty">Rename_dto</span>.t)
    : (<span class="ty">Cat</span>.t, <span class="ty">Kre.Error</span>.t) result <span class="ty">Lwt</span>.t =
  <span class="ty">Cats</span>.rename cat.id body
<span class="attr">[@@put ":cat"]</span>
<span class="attr">[@@authorize fun ~user ~cat -> Auth.owner_or_admin ~user cat]</span></pre>
  </div>
  <div class="term">
<pre><span class="pr">$</span> kre generate controller dogs name:string age:int
<span class="ok">created</span> ./server/dogs_controller.ml
<span class="ok">created</span> ./shared/dog.ml
<span class="ok">created</span> ./server/dogs_service.ml
<span class="pr">$</span> dune test
  <span class="ok">[OK]</span> crud 0 create, read, remove.</pre>
  </div>
  </div>
</section>

<section class="band">
  <div><b>0</b><span>runtime containers</span></div>
  <div><b>1</b><span>type per entity</span></div>
  <div><b>2</b><span>compile targets</span></div>
  <div><b>2</b><span>databases</span></div>
</section>

<section class="section">
  <div class="section-head">
    <div><div class="num">01</div><h2>A record is the contract.</h2></div>
    <p>The type in <code>shared/</code> compiles natively for the server and to JavaScript for the browser. Everything that crosses a boundary is derived from it, so the layers cannot drift apart.</p>
  </div>
  <TypeFanout />
</section>

<section class="section">
  <div class="section-head">
    <div><div class="num">02</div><h2>Three rules, no exceptions.</h2></div>
    <p>kre is built from functions, modules, functors and ppx rewrites. There are no classes, no reflection and nothing resolved at runtime that could have been checked at compile time.</p>
  </div>
  <div class="principles">
    <div>
      <span class="k">types</span>
      <h3>Types are the truth</h3>
      <p>Tables, JSON, OpenAPI and clients are derived from records. Nothing is written twice, so nothing can disagree.</p>
    </div>
    <div>
      <span class="k">wiring</span>
      <h3>Wiring is compiled</h3>
      <p>Providers are functors. <code>[%wire]</code> applies them at build time; a missing or ambiguous one is a compile error with a location.</p>
    </div>
    <div>
      <span class="k">input</span>
      <h3>Parse at the edge</h3>
      <p>Bodies, paths, queries and options become refined types once. After that the core never checks again.</p>
    </div>
  </div>
</section>

<section class="section">
  <div class="section-head">
    <div><div class="num">03</div><h2>Batteries, typed.</h2></div>
    <p>The pieces a real application needs are part of the framework and follow the same rules: declared next to your code, checked when it compiles.</p>
  </div>
  <Capabilities />
</section>

<section class="section">
  <div class="section-head">
    <div><div class="num">04</div><h2>The life of a request.</h2></div>
    <p>Every stage is declared next to the handler and generated at compile time. The right column shows how each stage answers when it says no.</p>
  </div>
  <RequestPipeline />
</section>

<section class="section">
  <div class="section-head">
    <div><div class="num">05</div><h2>Caught before it runs.</h2></div>
    <p>The checks kre makes on your behalf, and where they happen. Most stop the build; the rest fail the test suite with a precise message.</p>
  </div>
  <CompileVsRuntime />
</section>

<section class="section">
  <div class="section-head">
    <div><div class="num">06</div><h2>How it fits together.</h2></div>
    <p>Four layers, one repository. Shared code builds twice; the build step produces the routes, the API document, the dependency graph and the checked SQL.</p>
  </div>
  <Layers />
</section>

<section class="closing">
  <h2>Start with one record.</h2>
  <p>Create a project, add a resource and run its tests in a few minutes.</p>
  <div class="actions">
    <a class="primary" href="/guide/getting-started">Get started</a>
    <a href="/guide/introduction">Read the introduction</a>
  </div>
</section>

</div>
</template>

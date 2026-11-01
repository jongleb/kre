<script setup lang="ts">
const layers = [
  { name: 'client/', runs: 'Melange · React', items: ['Typed page router', 'Generated API clients', 'Pages in .mlx', 'Live updates over SSE'] },
  { name: 'shared/', runs: 'native and Melange', items: ['Records with [@@deriving dto]', 'Refined and opaque types', 'Search records, pages, time', 'Workflows'] },
  { name: 'server/', runs: 'Dream · Lwt', items: ['Controllers', 'Providers wired by [%wire]', 'sqlgg queries, jobs, mail', 'MariaDB or PostgreSQL'] },
  { name: 'build', runs: 'kre-ppx · sqlgg · kre CLI', items: ['Routes, specs, OpenAPI', 'Dependency graph', 'SQL checked against the schema', 'Migrations checked against types'] }
]
</script>

<template>
  <figure class="layers">
    <div v-for="(layer, index) in layers" :key="layer.name" class="layer">
      <div class="left">
        <span class="i">L{{ layers.length - index }}</span>
        <div>
          <div class="name">{{ layer.name }}</div>
          <div class="runs">{{ layer.runs }}</div>
        </div>
      </div>
      <ul>
        <li v-for="item in layer.items" :key="item">{{ item }}</li>
      </ul>
    </div>
  </figure>
</template>

<style scoped>
.layers {
  margin: 28px 0;
  border: 1px solid var(--k-border);
  border-radius: var(--k-radius);
  overflow: hidden;
  background: var(--k-bg);
}
.layer {
  display: grid;
  grid-template-columns: 240px 1fr;
  gap: 20px;
  align-items: center;
  padding: 18px 20px;
}
.layer + .layer { border-top: 1px solid var(--k-border); }
.left {
  display: flex;
  gap: 14px;
  align-items: center;
}
.i {
  font-family: var(--vp-font-family-mono);
  font-size: 11px;
  color: var(--k-text-3);
  border: 1px solid var(--k-border-strong);
  border-radius: 6px;
  padding: 3px 6px;
}
.name {
  font-family: var(--vp-font-family-mono);
  font-size: 14.5px;
  font-weight: 500;
  color: var(--k-text);
}
.runs {
  font-size: 12.5px;
  color: var(--k-text-3);
  margin-top: 2px;
}
ul {
  list-style: none;
  margin: 0 !important;
  padding: 0 !important;
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
}
li {
  margin: 0 !important;
  font-size: 13px;
  line-height: 1.4 !important;
  padding: 5px 10px;
  border-radius: 6px;
  color: var(--k-text-2);
  background: var(--k-surface);
  border: 1px solid var(--k-border);
}
@media (max-width: 760px) {
  .layer { grid-template-columns: 1fr; }
}
</style>

<script setup lang="ts">
const layers = [
  { name: 'client/', runs: 'Browser · Melange + React', items: ['Typed page router', 'Generated API clients', 'Pages in .mlx', 'Live updates over SSE'], tone: 'violet' },
  { name: 'shared/', runs: 'Native and Melange, same sources', items: ['Records with [@@deriving dto]', 'Refined & opaque types', 'Search records, pages, time', 'Workflows'], tone: 'ember' },
  { name: 'server/', runs: 'Native · Dream + Lwt', items: ['Controllers', 'Providers wired by [%wire]', 'sqlgg queries, jobs, mail', 'MariaDB or PostgreSQL'], tone: 'sky' },
  { name: 'build time', runs: 'kre-ppx · sqlgg · kre CLI', items: ['Routes, specs, OpenAPI', 'Dependency graph', 'SQL checked against schema', 'Migrations checked against types'], tone: 'mint' }
]
</script>

<template>
  <div class="layers">
    <div v-for="(layer, index) in layers" :key="layer.name" class="layer" :class="layer.tone" :style="{ '--i': index }">
      <div class="left">
        <div class="name">{{ layer.name }}</div>
        <div class="runs">{{ layer.runs }}</div>
      </div>
      <div class="items">
        <span v-for="item in layer.items" :key="item">{{ item }}</span>
      </div>
    </div>
  </div>
</template>

<style scoped>
.layers {
  display: flex;
  flex-direction: column;
  gap: 10px;
  margin: 24px 0;
  perspective: 900px;
}
.layer {
  --tone: var(--kre-ember);
  display: grid;
  grid-template-columns: 220px 1fr;
  gap: 16px;
  align-items: center;
  padding: 16px 20px;
  border-radius: 16px;
  border: 1px solid color-mix(in srgb, var(--tone) 40%, transparent);
  background: linear-gradient(90deg, color-mix(in srgb, var(--tone) 18%, transparent), var(--vp-c-bg-soft) 70%);
  margin-left: calc(var(--i) * 14px);
  margin-right: calc((3 - var(--i)) * 14px);
  transition: transform 0.2s ease;
}
.layer:hover { transform: translateX(6px); }
.layer.violet { --tone: var(--kre-violet); }
.layer.sky { --tone: var(--kre-sky); }
.layer.mint { --tone: var(--kre-mint); }
.name {
  font: 800 18px var(--vp-font-family-mono);
  color: var(--tone);
}
.runs {
  font-size: 12.5px;
  color: var(--vp-c-text-2);
  margin-top: 2px;
}
.items {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}
.items span {
  font-size: 12.5px;
  padding: 5px 10px;
  border-radius: 999px;
  color: var(--vp-c-text-1);
  background: rgba(255, 255, 255, 0.05);
  border: 1px solid var(--kre-line);
}
@media (max-width: 760px) {
  .layer { grid-template-columns: 1fr; margin: 0; }
}
</style>

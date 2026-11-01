<script setup lang="ts">
const left = [
  { title: 'CREATE TABLE', sub: 'Kre.Table.schema prints the DDL and the migration', tone: 'amber' },
  { title: 'Checked SQL', sub: 'sqlgg types every query against that schema', tone: 'ember' },
  { title: 'CRUD + finders', sub: 'insert, update, by_email, page, count', tone: 'magma' }
]
const right = [
  { title: 'JSON + validation', sub: 'parse, don’t validate: 422 with field paths', tone: 'mint' },
  { title: 'OpenAPI 3.1', sub: 'schemas and parameters from the same type', tone: 'sky' },
  { title: 'Typed client & router', sub: 'Melange in the browser, the very same record', tone: 'violet' }
]
</script>

<template>
  <div class="fanout">
    <div class="side left">
      <div v-for="item in left" :key="item.title" class="out" :class="item.tone">
        <div class="t">{{ item.title }}</div>
        <div class="s">{{ item.sub }}</div>
      </div>
    </div>
    <div class="core">
      <div class="glow" />
      <div class="card">
        <div class="file">shared/cat.ml</div>
<pre><span class="k">type</span> t = {
  id : <span class="m">Id</span>.t; <span class="a">[@primary] [@auto]</span>
  name : <span class="m">Name</span>.t;
  status : <span class="m">Status</span>.t; <span class="a">[@index]</span>
  owner_id : <span class="m">User.Id</span>.t option;
  version : int; <span class="a">[@version]</span>
}
<span class="a">[@@deriving table, dto]</span></pre>
        <div class="one">one type</div>
      </div>
    </div>
    <div class="side right">
      <div v-for="item in right" :key="item.title" class="out" :class="item.tone">
        <div class="t">{{ item.title }}</div>
        <div class="s">{{ item.sub }}</div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.fanout {
  display: grid;
  grid-template-columns: 1fr 1.25fr 1fr;
  gap: 34px;
  align-items: center;
  margin: 10px 0 20px;
}
.side {
  display: flex;
  flex-direction: column;
  gap: 16px;
}
.out {
  --tone: var(--kre-ember);
  position: relative;
  padding: 14px 16px;
  border-radius: 14px;
  border: 1px solid color-mix(in srgb, var(--tone) 40%, transparent);
  background: linear-gradient(160deg, color-mix(in srgb, var(--tone) 14%, transparent), rgba(255, 255, 255, 0.01));
  transition: transform 0.2s ease;
}
.out:hover { transform: scale(1.03); }
.out.amber { --tone: var(--kre-amber); }
.out.magma { --tone: var(--kre-magma); }
.out.mint { --tone: var(--kre-mint); }
.out.sky { --tone: var(--kre-sky); }
.out.violet { --tone: var(--kre-violet); }
.out::after {
  content: '';
  position: absolute;
  top: 50%;
  width: 34px;
  height: 2px;
  background-size: 200% 100%;
  animation: flow 1.4s linear infinite;
}
.left .out::after {
  right: -35px;
  background-image: linear-gradient(270deg, var(--tone), transparent, var(--tone));
}
.right .out::after {
  left: -35px;
  background-image: linear-gradient(90deg, var(--tone), transparent, var(--tone));
}
@keyframes flow {
  from { background-position: 0 0; }
  to { background-position: 200% 0; }
}
.t {
  font-weight: 800;
  color: var(--vp-c-text-1);
  font-size: 15px;
}
.s {
  margin-top: 4px;
  font-size: 12.5px;
  line-height: 1.45;
  color: var(--vp-c-text-2);
}
.core {
  position: relative;
}
.glow {
  position: absolute;
  inset: -30px;
  background: radial-gradient(circle, rgba(255, 122, 24, 0.35), transparent 65%);
  filter: blur(20px);
  animation: pulse 3.2s ease-in-out infinite;
}
@keyframes pulse {
  0%, 100% { opacity: 0.6; }
  50% { opacity: 1; }
}
.card {
  position: relative;
  border-radius: 18px;
  padding: 16px 18px 14px;
  border: 1px solid rgba(255, 122, 24, 0.55);
  background: #0e1118;
  box-shadow: 0 30px 60px -30px rgba(255, 122, 24, 0.6);
}
.file {
  font: 600 11px var(--vp-font-family-mono);
  color: var(--vp-c-text-3);
  margin-bottom: 8px;
}
pre {
  margin: 0;
  font: 13px/1.6 var(--vp-font-family-mono);
  color: #d8dee9;
  white-space: pre;
  overflow-x: auto;
}
.k { color: #c678dd; }
.m { color: #61afef; }
.a { color: #ffb86b; }
.one {
  position: absolute;
  top: -12px;
  right: 16px;
  padding: 3px 10px;
  border-radius: 999px;
  font: 800 11px var(--vp-font-family-base);
  letter-spacing: 0.1em;
  text-transform: uppercase;
  color: #0b0d12;
  background: var(--kre-gradient);
}
@media (max-width: 860px) {
  .fanout { grid-template-columns: 1fr; gap: 18px; }
  .out::after { display: none; }
  .core { order: -1; }
}
</style>

<script setup lang="ts">
const left = [
  { kind: 'schema', title: 'CREATE TABLE', sub: 'DDL and the first migration, printed from the record' },
  { kind: 'sql', title: 'Checked queries', sub: 'sqlgg types every query against that schema' },
  { kind: 'crud', title: 'CRUD and finders', sub: 'insert, update, by_status, page, count' }
]
const right = [
  { kind: 'json', title: 'JSON with validation', sub: 'parsed at the edge, 422 with field paths' },
  { kind: 'openapi', title: 'OpenAPI 3.1', sub: 'schemas and parameters, no annotations' },
  { kind: 'client', title: 'Browser client', sub: 'the same record, compiled with Melange' }
]
</script>

<template>
  <figure class="fanout">
    <div class="side left">
      <div v-for="item in left" :key="item.title" class="out">
        <span class="kind">{{ item.kind }}</span>
        <div class="t">{{ item.title }}</div>
        <div class="s">{{ item.sub }}</div>
        <i class="wire" />
      </div>
    </div>
    <div class="core">
      <div class="file"><span>shared/cat.ml</span><span class="tag">source of truth</span></div>
<pre><span class="kw">type</span> t = {
  id : <span class="ty">Id</span>.t; <span class="at">[@primary] [@auto]</span>
  name : <span class="ty">Name</span>.t;
  status : <span class="ty">Status</span>.t; <span class="at">[@index]</span>
  owner_id : <span class="ty">User.Id</span>.t option;
  version : int; <span class="at">[@version]</span>
}
<span class="at">[@@deriving table, dto]</span></pre>
    </div>
    <div class="side right">
      <div v-for="item in right" :key="item.title" class="out">
        <span class="kind">{{ item.kind }}</span>
        <div class="t">{{ item.title }}</div>
        <div class="s">{{ item.sub }}</div>
        <i class="wire" />
      </div>
    </div>
  </figure>
</template>

<style scoped>
.fanout {
  display: grid;
  grid-template-columns: 1fr 1.15fr 1fr;
  gap: 44px;
  align-items: center;
  margin: 28px 0;
}
.side {
  display: flex;
  flex-direction: column;
  gap: 14px;
}
.out {
  position: relative;
  padding: 14px 16px;
  border: 1px solid var(--k-border);
  border-radius: var(--k-radius);
  background: var(--k-bg);
  transition: border-color 0.15s;
}
.out:hover { border-color: var(--k-text-3); }
.kind {
  font-family: var(--vp-font-family-mono);
  font-size: 11px;
  color: var(--k-text-3);
}
.t {
  margin-top: 4px;
  font-weight: 600;
  font-size: 14.5px;
  letter-spacing: -0.01em;
  color: var(--k-text);
}
.s {
  margin-top: 3px;
  font-size: 13px;
  line-height: 1.5;
  color: var(--k-text-2);
}
.wire {
  position: absolute;
  top: 50%;
  width: 44px;
  height: 1px;
  background: var(--k-border-strong);
}
.wire::after {
  content: '';
  position: absolute;
  top: -3px;
  width: 7px;
  height: 7px;
  border-radius: 2px;
  background: var(--k-bg);
  border: 1px solid var(--k-text-3);
}
.left .wire { right: -45px; }
.left .wire::after { right: -4px; }
.right .wire { left: -45px; }
.right .wire::after { left: -4px; }
.core {
  border: 1px solid var(--k-text);
  border-radius: 12px;
  background: var(--k-surface);
  overflow: hidden;
}
.file {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 10px 14px;
  border-bottom: 1px solid var(--k-border);
  font-family: var(--vp-font-family-mono);
  font-size: 11.5px;
  color: var(--k-text-3);
}
.tag { color: var(--k-accent); }
pre {
  margin: 0;
  padding: 16px 16px 18px;
  font: 12.5px/1.75 var(--vp-font-family-mono);
  color: var(--k-text);
  overflow-x: auto;
}
.kw { color: #c2410c; }
.ty { color: #2563eb; }
.at { color: var(--k-text-3); }
:global(.dark) .kw { color: #ff8f73; }
:global(.dark) .ty { color: #7cb3ff; }
@media (max-width: 900px) {
  .fanout { grid-template-columns: 1fr; gap: 14px; }
  .core { order: -1; }
  .wire { display: none; }
}
</style>

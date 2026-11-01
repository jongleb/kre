<script setup lang="ts">
const stages = [
  { name: 'Route', attr: '[@@get ":cat"]', fail: '404', note: 'Typed segments: an id that does not parse never matches.' },
  { name: 'Middleware', attr: '[@@@use] [@@etag]', fail: '304', note: 'Logging, profiler, ETag, CORS, rate limits.' },
  { name: 'Guards', attr: '[@guard Auth.current]', fail: '401 · 403', note: 'Return evidence, such as Auth.Admin.t, or stop the request.' },
  { name: 'Parse', attr: '~body [@search]', fail: '400 · 422', note: 'Path, query, headers and body become types; every error is reported.' },
  { name: 'Load', attr: '[@load Cats.find]', fail: '404', note: 'The :cat segment becomes a Cat.t before your code runs.' },
  { name: 'Authorize', attr: '[@@authorize]', fail: '403', note: 'A typed check over the parsed arguments.' },
  { name: 'Transaction', attr: '[@@transactional]', fail: 'rollback', note: 'Ok commits, Error rolls back; services join the same connection.' },
  { name: 'Interceptors', attr: '[@@intercept]', fail: '504', note: 'Timing, timeouts and error mapping around the typed result.' },
  { name: 'Handler', attr: 'Cat.t Lwt.t', fail: '', note: 'A plain function. Its return type decides the response.' },
  { name: 'Response', attr: 'JSON · Problem Details', fail: '', note: 'Errors are RFC 9457 documents that the client parses back.' }
]
</script>

<template>
  <figure class="pipe">
    <div v-for="(stage, index) in stages" :key="stage.name" class="row">
      <div class="rail"><span class="node" :class="{ last: index === stages.length - 1 }" /></div>
      <div class="n">{{ String(index + 1).padStart(2, '0') }}</div>
      <div class="what">
        <div class="name">{{ stage.name }}</div>
        <code>{{ stage.attr }}</code>
      </div>
      <div class="note">{{ stage.note }}</div>
      <div class="fail">{{ stage.fail }}</div>
    </div>
  </figure>
</template>

<style scoped>
.pipe {
  margin: 28px 0;
  border: 1px solid var(--k-border);
  border-radius: var(--k-radius);
  background: var(--k-bg);
  padding: 8px 0;
}
.row {
  display: grid;
  grid-template-columns: 28px 34px minmax(170px, 0.9fr) 1.6fr 76px;
  align-items: center;
  gap: 14px;
  padding: 11px 20px 11px 12px;
  transition: background 0.15s;
}
.row:hover { background: var(--k-surface); }
.rail {
  position: relative;
  align-self: stretch;
  display: flex;
  justify-content: center;
}
.rail::before {
  content: '';
  position: absolute;
  top: -12px;
  bottom: -12px;
  width: 1px;
  background: var(--k-border-strong);
}
.row:first-child .rail::before { top: 50%; }
.row:last-child .rail::before { bottom: 50%; }
.node {
  position: relative;
  align-self: center;
  width: 9px;
  height: 9px;
  border-radius: 3px;
  background: var(--k-bg);
  border: 1px solid var(--k-text-3);
}
.node.last { background: var(--k-accent); border-color: var(--k-accent); }
.n {
  font-family: var(--vp-font-family-mono);
  font-size: 11.5px;
  color: var(--k-text-3);
}
.name {
  font-weight: 600;
  font-size: 14.5px;
  color: var(--k-text);
}
code {
  display: inline-block;
  margin-top: 3px;
  font-family: var(--vp-font-family-mono);
  font-size: 11.5px;
  color: var(--k-text-2);
}
.note {
  font-size: 13.5px;
  line-height: 1.5;
  color: var(--k-text-2);
}
.fail {
  justify-self: end;
  font-family: var(--vp-font-family-mono);
  font-size: 11.5px;
  color: var(--k-accent);
  white-space: nowrap;
}
@media (max-width: 760px) {
  .row { grid-template-columns: 22px 1fr 60px; }
  .n, .note { display: none; }
}
</style>

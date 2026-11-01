<script setup lang="ts">
const stages = [
  { name: 'Route', attr: '[@@get ":cat"]', fail: '404', tone: 'sky', note: 'Typed segments: a cat id that is not a number never matches.' },
  { name: 'Middleware', attr: '[@@@use] · [@@etag]', fail: '304', tone: 'violet', note: 'Logging, profiler, ETag, rate limits, CORS — plain Dream middleware.' },
  { name: 'Guards', attr: '[@guard Auth.current]', fail: '401 / 403', tone: 'magma', note: 'A guard returns evidence, like an Admin.t, or the request stops.' },
  { name: 'Parse', attr: '~body · [@search]', fail: '400 / 422', tone: 'amber', note: 'Path, query, body, headers: parsed into types, every error at once.' },
  { name: 'Load', attr: '[@load Cats.find]', fail: '404', tone: 'ember', note: 'The :cat segment becomes a Cat.t before your code runs.' },
  { name: 'Authorize', attr: '[@@authorize]', fail: '403', tone: 'magma', note: 'A typed check over the parsed arguments: owner or admin?' },
  { name: 'Transaction', attr: '[@@transactional]', fail: 'rollback', tone: 'amber', note: 'Ok commits, Error rolls back; every service joins the same connection.' },
  { name: 'Interceptors', attr: '[@@intercept] · [@@retry]', fail: '504', tone: 'violet', note: 'Timing, timeouts, error mapping around the typed result.' },
  { name: 'Your handler', attr: 'Cat.t Lwt.t', fail: '', tone: 'mint', note: 'Just a function. Its return type decides the response.' },
  { name: 'Response', attr: 'JSON · Problem Details', fail: '', tone: 'sky', note: 'Errors are RFC 9457 Problem Details, parsed back by the client.' }
]
</script>

<template>
  <div class="pipeline">
    <div class="rail"><div class="packet" /></div>
    <div class="stages">
      <div v-for="(stage, index) in stages" :key="stage.name" class="stage" :class="stage.tone">
        <div class="num">{{ index + 1 }}</div>
        <div class="name">{{ stage.name }}</div>
        <code class="attr">{{ stage.attr }}</code>
        <div class="note">{{ stage.note }}</div>
        <div v-if="stage.fail" class="fail">{{ stage.fail }}</div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.pipeline {
  position: relative;
  margin: 24px 0;
  padding: 26px 18px 20px;
  border-radius: 20px;
  border: 1px solid var(--kre-line);
  background:
    radial-gradient(900px 260px at 50% 0%, rgba(255, 122, 24, 0.09), transparent 70%),
    var(--vp-c-bg-soft);
}
.rail {
  position: absolute;
  left: 30px;
  right: 30px;
  top: 40px;
  height: 2px;
  background: linear-gradient(90deg, var(--kre-sky), var(--kre-ember), var(--kre-mint));
  opacity: 0.45;
}
.packet {
  position: absolute;
  top: -4px;
  width: 10px;
  height: 10px;
  border-radius: 50%;
  background: #fff;
  box-shadow: 0 0 16px 4px rgba(255, 194, 75, 0.9);
  animation: run 6s linear infinite;
}
@keyframes run {
  from { left: 0; }
  to { left: 100%; }
}
.stages {
  position: relative;
  display: grid;
  grid-template-columns: repeat(5, 1fr);
  gap: 14px;
}
.stage {
  --tone: var(--kre-ember);
  position: relative;
  padding: 12px 12px 14px;
  border-radius: 14px;
  border: 1px solid color-mix(in srgb, var(--tone) 35%, transparent);
  background: linear-gradient(170deg, color-mix(in srgb, var(--tone) 13%, var(--vp-c-bg-soft)), var(--vp-c-bg-soft));
  transition: transform 0.2s ease, box-shadow 0.2s ease;
}
.stage:hover {
  transform: translateY(-4px);
  box-shadow: 0 16px 30px -18px var(--tone);
}
.stage.sky { --tone: var(--kre-sky); }
.stage.violet { --tone: var(--kre-violet); }
.stage.magma { --tone: var(--kre-magma); }
.stage.amber { --tone: var(--kre-amber); }
.stage.mint { --tone: var(--kre-mint); }
.num {
  width: 26px;
  height: 26px;
  border-radius: 8px;
  display: grid;
  place-items: center;
  font: 800 12px var(--vp-font-family-mono);
  color: #0b0d12;
  background: var(--tone);
  box-shadow: 0 0 14px color-mix(in srgb, var(--tone) 70%, transparent);
}
.name {
  margin-top: 10px;
  font-weight: 800;
  color: var(--vp-c-text-1);
}
.attr {
  display: inline-block;
  margin-top: 6px;
  font-size: 11px;
  color: var(--tone);
  background: rgba(0, 0, 0, 0.25);
  padding: 2px 6px;
  border-radius: 6px;
}
.note {
  margin-top: 8px;
  font-size: 12px;
  line-height: 1.45;
  color: var(--vp-c-text-2);
}
.fail {
  position: absolute;
  top: 10px;
  right: 10px;
  font: 800 10.5px var(--vp-font-family-mono);
  color: #ff6b81;
  padding: 2px 6px;
  border-radius: 6px;
  background: rgba(255, 46, 99, 0.12);
}
@media (max-width: 960px) {
  .stages { grid-template-columns: repeat(2, 1fr); }
  .rail { display: none; }
}
</style>

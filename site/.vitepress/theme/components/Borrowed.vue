<script setup lang="ts">
const sources = [
  {
    name: 'NestJS',
    color: '#e0234e',
    gave: ['Controllers & decorators', 'Guards, pipes, interceptors', 'Modules → [%wire]', 'Typed DTOs → [@@deriving dto]', 'Gateways & SSE', 'Generated clients']
  },
  {
    name: 'Spring',
    color: '#6db33f',
    gave: ['@Transactional', '@PreAuthorize → [@@authorize]', 'Actuator & /beans', 'Problem Details', 'Derived finders', 'Pageable', '@Retryable', '@HttpExchange']
  },
  {
    name: 'Rails',
    color: '#d30001',
    gave: ['Scaffold generator', 'Timestamps & lock_version', 'Solid Queue jobs', 'ActionMailer previews', 'rake tasks → commands', 'fresh_when / ETag']
  },
  {
    name: 'Symfony',
    color: '#9c8cff',
    gave: ['#[MapEntity] → [@load]', '#[MapQueryString] → [@search]', 'Workflow component', 'Web Profiler', 'Console commands', 'Messenger retries']
  },
  {
    name: 'IHP',
    color: '#ff9f43',
    gave: ['Auto Refresh → live loaders', 'Jobs as tables', 'Scripts', 'Type-safe everything']
  }
]
</script>

<template>
  <div class="borrowed">
    <div v-for="source in sources" :key="source.name" class="source" :style="{ '--c': source.color }">
      <div class="name"><span class="badge" />{{ source.name }}</div>
      <ul>
        <li v-for="item in source.gave" :key="item">{{ item }}</li>
      </ul>
    </div>
    <div class="into">
      <div class="arrow">↓ rewritten as functions, modules, functors and ppx ↓</div>
      <div class="kre">Kre</div>
    </div>
  </div>
</template>

<style scoped>
.borrowed {
  display: grid;
  grid-template-columns: repeat(5, 1fr);
  gap: 12px;
}
.source {
  padding: 16px;
  border-radius: 16px;
  border: 1px solid color-mix(in srgb, var(--c) 40%, transparent);
  background: linear-gradient(170deg, color-mix(in srgb, var(--c) 14%, transparent), var(--vp-c-bg-soft) 60%);
}
.name {
  font-weight: 900;
  font-size: 17px;
  color: var(--vp-c-text-1);
  display: flex;
  align-items: center;
  gap: 8px;
}
.badge {
  width: 10px;
  height: 10px;
  border-radius: 3px;
  background: var(--c);
  box-shadow: 0 0 12px var(--c);
}
ul {
  margin: 12px 0 0;
  padding: 0;
  list-style: none;
}
li {
  font-size: 13px;
  line-height: 1.35;
  padding: 6px 0;
  color: var(--vp-c-text-2);
  border-top: 1px dashed var(--kre-line);
}
.into {
  grid-column: 1 / -1;
  text-align: center;
  margin-top: 6px;
}
.arrow {
  font-size: 13px;
  font-weight: 700;
  color: var(--vp-c-text-3);
  letter-spacing: 0.04em;
}
.kre {
  display: inline-block;
  margin-top: 10px;
  padding: 10px 34px;
  border-radius: 999px;
  font-weight: 900;
  font-size: 22px;
  letter-spacing: -0.02em;
  color: #0b0d12;
  background: var(--kre-gradient);
  box-shadow: 0 18px 50px -12px rgba(255, 122, 24, 0.75);
}
@media (max-width: 960px) {
  .borrowed { grid-template-columns: repeat(2, 1fr); }
}
</style>

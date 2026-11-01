<script setup lang="ts">
const checks = [
  { mistake: 'A service needs a provider nobody wrote', where: 'build', how: 'The functor application [%wire] writes does not compile; the error points at the parameter.' },
  { mistake: 'A column is renamed', where: 'build', how: 'sqlgg rejects every query that still uses the old name.' },
  { mistake: 'A handler skips the admin check', where: 'build', how: 'Auth.Admin.t comes only from the admin guard; without it the call does not type-check.' },
  { mistake: 'A link is built with the wrong params', where: 'build', how: 'Routes are typed values; href and navigate check params and search.' },
  { mistake: 'A workflow state is misspelled', where: 'build', how: 'Transitions are patterns over the constructors.' },
  { mistake: 'A live page forgets a table it reads', where: 'test', how: 'Under KRE_ENV=test the route answers 500 and names the table.' }
]
</script>

<template>
  <figure class="checks">
    <div class="head">
      <span>If you</span><span>Caught at</span><span>How</span>
    </div>
    <div v-for="check in checks" :key="check.mistake" class="row">
      <div class="mistake">{{ check.mistake.toLowerCase() }}</div>
      <div><span class="badge" :class="check.where">{{ check.where === 'build' ? 'compile time' : 'dune test' }}</span></div>
      <div class="how">{{ check.how }}</div>
    </div>
  </figure>
</template>

<style scoped>
.checks {
  margin: 28px 0;
  border: 1px solid var(--k-border);
  border-radius: var(--k-radius);
  overflow: hidden;
  background: var(--k-bg);
}
.head,
.row {
  display: grid;
  grid-template-columns: 1.1fr 140px 1.6fr;
  gap: 18px;
  padding: 13px 20px;
  align-items: center;
}
.head {
  background: var(--k-surface);
  border-bottom: 1px solid var(--k-border);
  font-size: 12.5px;
  font-weight: 500;
  color: var(--k-text-3);
}
.row + .row { border-top: 1px solid var(--k-border); }
.mistake {
  font-weight: 500;
  font-size: 14.5px;
  color: var(--k-text);
}
.mistake::first-letter { text-transform: uppercase; }
.how {
  font-size: 13.5px;
  line-height: 1.55;
  color: var(--k-text-2);
}
.badge {
  display: inline-flex;
  align-items: center;
  gap: 7px;
  font-family: var(--vp-font-family-mono);
  font-size: 11.5px;
  color: var(--k-text);
  padding: 3px 9px;
  border: 1px solid var(--k-border-strong);
  border-radius: 999px;
}
.badge::before {
  content: '';
  width: 6px;
  height: 6px;
  border-radius: 2px;
  background: var(--k-accent);
}
.badge.test::before { background: var(--k-good); }
@media (max-width: 760px) {
  .head { display: none; }
  .row { grid-template-columns: 1fr; gap: 6px; }
}
</style>

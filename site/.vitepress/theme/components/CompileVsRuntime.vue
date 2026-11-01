<script setup lang="ts">
const mistakes = [
  { what: 'A service needs a provider nobody wrote', other: 'The app boots, then crashes resolving the container', kre: 'Compile error at the functor parameter' },
  { what: 'A column is renamed', other: 'The query fails the first time it runs in production', kre: 'sqlgg rejects every query that still uses it' },
  { what: 'A table changes, no migration', other: 'Schema drift found on deploy', kre: 'dune test fails with the missing migration as a diff' },
  { what: 'A link passes the wrong params', other: '404 when somebody clicks it', kre: 'Type error in the page that builds the link' },
  { what: 'A workflow state is misspelled', other: 'String config, discovered at runtime', kre: 'The transition is a pattern: it does not compile' },
  { what: 'A live page forgets a table', other: 'The page silently goes stale', kre: 'The e2e test answers 500 naming the table' }
]
</script>

<template>
  <div class="cvr">
    <div class="legend">
      <span class="r">found in production</span>
      <span class="g">found by the compiler or the test suite</span>
    </div>
    <div class="grid">
      <div v-for="m in mistakes" :key="m.what" class="item">
        <div class="what">{{ m.what }}</div>
        <div class="line other"><span class="dot" />{{ m.other }}</div>
        <div class="line kre"><span class="dot" />{{ m.kre }}</div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.legend {
  display: flex;
  gap: 18px;
  flex-wrap: wrap;
  margin-bottom: 14px;
  font-size: 13px;
  font-weight: 700;
}
.legend span::before {
  content: '';
  display: inline-block;
  width: 10px;
  height: 10px;
  border-radius: 50%;
  margin-right: 8px;
  vertical-align: -1px;
}
.legend .r { color: #ff6b81; }
.legend .r::before { background: #ff2e63; box-shadow: 0 0 10px #ff2e63; }
.legend .g { color: var(--kre-mint); }
.legend .g::before { background: var(--kre-mint); box-shadow: 0 0 10px var(--kre-mint); }
.grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
  gap: 14px;
}
.item {
  padding: 18px;
  border-radius: 16px;
  border: 1px solid var(--kre-line);
  background: var(--vp-c-bg-soft);
  transition: border-color 0.2s ease;
}
.item:hover { border-color: rgba(61, 220, 151, 0.45); }
.what {
  font-weight: 800;
  color: var(--vp-c-text-1);
  margin-bottom: 12px;
}
.line {
  display: flex;
  gap: 10px;
  align-items: flex-start;
  font-size: 13.5px;
  line-height: 1.45;
  padding: 8px 10px;
  border-radius: 10px;
}
.line + .line { margin-top: 6px; }
.dot {
  flex: 0 0 8px;
  height: 8px;
  margin-top: 6px;
  border-radius: 50%;
}
.other { color: var(--vp-c-text-2); background: rgba(255, 46, 99, 0.06); text-decoration: line-through; text-decoration-color: rgba(255, 46, 99, 0.5); }
.other .dot { background: #ff2e63; }
.kre { color: var(--vp-c-text-1); background: rgba(61, 220, 151, 0.07); }
.kre .dot { background: var(--kre-mint); box-shadow: 0 0 8px var(--kre-mint); }
</style>

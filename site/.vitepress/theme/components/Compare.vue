<script setup lang="ts">
type Row = { topic: string; elsewhere: string; kre: string }
withDefaults(defineProps<{ rows: Row[]; left?: string; right?: string }>(), {
  left: 'Elsewhere',
  right: 'Kre'
})
</script>

<template>
  <div class="compare">
    <div class="head">
      <span />
      <span class="left">{{ left }}</span>
      <span class="right">{{ right }}</span>
    </div>
    <div v-for="row in rows" :key="row.topic" class="row">
      <div class="topic">{{ row.topic }}</div>
      <div class="cell left"><span class="mark">✕</span>{{ row.elsewhere }}</div>
      <div class="cell right"><span class="mark">✓</span>{{ row.kre }}</div>
    </div>
  </div>
</template>

<style scoped>
.compare {
  margin: 24px 0;
  border-radius: 18px;
  border: 1px solid var(--kre-line);
  overflow: hidden;
  background: var(--vp-c-bg-soft);
}
.head,
.row {
  display: grid;
  grid-template-columns: 1.1fr 1.6fr 1.6fr;
}
.head span {
  padding: 12px 16px;
  font-size: 12px;
  font-weight: 800;
  letter-spacing: 0.12em;
  text-transform: uppercase;
}
.head .left { color: #ff6b81; }
.head .right { color: var(--kre-mint); }
.row {
  border-top: 1px solid var(--kre-line);
}
.row:hover { background: rgba(255, 255, 255, 0.02); }
.topic {
  padding: 14px 16px;
  font-weight: 700;
  color: var(--vp-c-text-1);
  font-size: 14px;
}
.cell {
  padding: 14px 16px;
  font-size: 13.5px;
  line-height: 1.5;
  color: var(--vp-c-text-2);
  display: flex;
  gap: 10px;
  align-items: flex-start;
}
.cell.left { background: rgba(255, 46, 99, 0.04); }
.cell.right { background: rgba(61, 220, 151, 0.05); color: var(--vp-c-text-1); }
.mark {
  flex: 0 0 20px;
  height: 20px;
  border-radius: 50%;
  display: grid;
  place-items: center;
  font-size: 11px;
  font-weight: 900;
}
.left .mark { background: rgba(255, 46, 99, 0.18); color: #ff6b81; }
.right .mark { background: rgba(61, 220, 151, 0.18); color: var(--kre-mint); }
@media (max-width: 720px) {
  .head { display: none; }
  .row { grid-template-columns: 1fr; }
}
</style>

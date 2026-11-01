<script setup lang="ts">
type Stat = { value: string; label: string; note?: string }
defineProps<{ stats: Stat[] }>()
</script>

<template>
  <div class="stats">
    <div v-for="stat in stats" :key="stat.label" class="stat">
      <div class="value" :class="{ long: stat.value.length > 5 }">{{ stat.value }}</div>
      <div class="label">{{ stat.label }}</div>
      <div v-if="stat.note" class="note">{{ stat.note }}</div>
    </div>
  </div>
</template>

<style scoped>
.stats {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
  margin: 28px 0;
  border-top: 1px solid var(--k-border);
  border-bottom: 1px solid var(--k-border);
}
.stat {
  padding: 20px 20px 20px 0;
}
.stat + .stat {
  padding-left: 20px;
  border-left: 1px solid var(--k-border);
}
.value {
  font-size: 40px;
  font-weight: 600;
  letter-spacing: -0.05em;
  line-height: 1;
  color: var(--k-text);
}
.value.long {
  font-family: var(--vp-font-family-mono);
  font-size: 20px;
  letter-spacing: -0.01em;
  line-height: 1.3;
  overflow-wrap: anywhere;
}
.label {
  margin-top: 12px;
  font-size: 14px;
  font-weight: 500;
  color: var(--k-text);
}
.note {
  margin-top: 4px;
  font-size: 13px;
  line-height: 1.5;
  color: var(--k-text-3);
}
@media (max-width: 640px) {
  .stat + .stat { border-left: none; padding-left: 0; border-top: 1px solid var(--k-border); }
}
</style>

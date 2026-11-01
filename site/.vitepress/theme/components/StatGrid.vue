<script setup lang="ts">
type Stat = { value: string; label: string; note?: string }
defineProps<{ stats: Stat[] }>()
</script>

<template>
  <div class="stats">
    <div v-for="stat in stats" :key="stat.label" class="stat">
      <div class="value">{{ stat.value }}</div>
      <div class="label">{{ stat.label }}</div>
      <div v-if="stat.note" class="note">{{ stat.note }}</div>
    </div>
  </div>
</template>

<style scoped>
.stats {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(190px, 1fr));
  gap: 14px;
  margin: 24px 0;
}
.stat {
  position: relative;
  padding: 22px 20px;
  border-radius: 18px;
  border: 1px solid var(--kre-line);
  background: linear-gradient(160deg, rgba(255, 122, 24, 0.08), rgba(255, 255, 255, 0.01));
  overflow: hidden;
}
.stat::after {
  content: '';
  position: absolute;
  inset: auto -30% -60% auto;
  width: 160px;
  height: 160px;
  border-radius: 50%;
  background: radial-gradient(circle, rgba(255, 122, 24, 0.25), transparent 70%);
}
.value {
  font-size: 44px;
  font-weight: 900;
  letter-spacing: -0.04em;
  line-height: 1;
  background: var(--kre-gradient);
  -webkit-background-clip: text;
  background-clip: text;
  color: transparent;
}
.label {
  margin-top: 10px;
  font-weight: 700;
  color: var(--vp-c-text-1);
}
.note {
  margin-top: 4px;
  font-size: 13px;
  color: var(--vp-c-text-2);
}
</style>

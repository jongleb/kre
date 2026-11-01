<script setup lang="ts">
type Step = { title: string; sub?: string; code?: string; tone?: 'ember' | 'amber' | 'mint' | 'sky' | 'violet' | 'magma' }
defineProps<{ steps: Step[]; caption?: string }>()
</script>

<template>
  <figure class="flow">
    <div class="track">
      <template v-for="(step, index) in steps" :key="index">
        <div class="step" :class="step.tone ?? 'ember'">
          <div class="index">{{ String(index + 1).padStart(2, '0') }}</div>
          <div class="title">{{ step.title }}</div>
          <code v-if="step.code" class="code">{{ step.code }}</code>
          <div v-if="step.sub" class="sub">{{ step.sub }}</div>
        </div>
        <div v-if="index < steps.length - 1" class="arrow"><span /></div>
      </template>
    </div>
    <figcaption v-if="caption">{{ caption }}</figcaption>
  </figure>
</template>

<style scoped>
.flow {
  margin: 24px 0;
  padding: 22px;
  border-radius: 18px;
  border: 1px solid var(--kre-line);
  background:
    radial-gradient(700px 220px at 50% 0%, rgba(255, 122, 24, 0.08), transparent 70%),
    var(--vp-c-bg-soft);
  overflow-x: auto;
}
.track {
  display: flex;
  flex-wrap: wrap;
  align-items: stretch;
  row-gap: 14px;
}
.step {
  --tone: var(--kre-ember);
  position: relative;
  flex: 1 1 130px;
  min-width: 130px;
  max-width: 230px;
  padding: 14px 14px 16px;
  border-radius: 14px;
  border: 1px solid color-mix(in srgb, var(--tone) 35%, transparent);
  background: linear-gradient(170deg, color-mix(in srgb, var(--tone) 16%, transparent), rgba(255, 255, 255, 0.015));
  transition: transform 0.2s ease, box-shadow 0.2s ease;
}
.step:hover {
  transform: translateY(-3px);
  box-shadow: 0 14px 30px -16px var(--tone);
}
.step.amber { --tone: var(--kre-amber); }
.step.mint { --tone: var(--kre-mint); }
.step.sky { --tone: var(--kre-sky); }
.step.violet { --tone: var(--kre-violet); }
.step.magma { --tone: var(--kre-magma); }
.index {
  font: 700 11px var(--vp-font-family-mono);
  color: var(--tone);
  letter-spacing: 0.1em;
}
.title {
  margin-top: 4px;
  font-weight: 800;
  font-size: 15px;
  line-height: 1.25;
  color: var(--vp-c-text-1);
}
.code {
  display: inline-block;
  margin-top: 8px;
  padding: 2px 6px;
  border-radius: 6px;
  font-size: 11.5px;
  color: var(--tone);
  background: rgba(0, 0, 0, 0.25);
}
.sub {
  margin-top: 8px;
  font-size: 12.5px;
  line-height: 1.45;
  color: var(--vp-c-text-2);
}
.arrow {
  flex: 0 0 26px;
  display: flex;
  align-items: center;
  justify-content: center;
}
.arrow span {
  position: relative;
  width: 22px;
  height: 2px;
  background: linear-gradient(90deg, transparent, var(--kre-ember));
  overflow: visible;
}
.arrow span::after {
  content: '';
  position: absolute;
  right: -2px;
  top: -4px;
  border-left: 7px solid var(--kre-ember);
  border-top: 5px solid transparent;
  border-bottom: 5px solid transparent;
}
.arrow span::before {
  content: '';
  position: absolute;
  top: -2px;
  left: 0;
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: var(--kre-amber);
  box-shadow: 0 0 10px var(--kre-amber);
  animation: travel 1.6s linear infinite;
}
@keyframes travel {
  from { left: 0; opacity: 0; }
  20% { opacity: 1; }
  to { left: 18px; opacity: 0; }
}
figcaption {
  margin-top: 14px;
  text-align: center;
  font-size: 13px;
  color: var(--vp-c-text-3);
}
</style>

<script setup lang="ts">
type Step = { title: string; sub?: string; code?: string; tone?: string }
defineProps<{ steps: Step[]; caption?: string }>()
</script>

<template>
  <figure class="flow">
    <ol>
      <li v-for="(step, index) in steps" :key="index">
        <div class="head">
          <span class="n">{{ String(index + 1).padStart(2, '0') }}</span>
          <span class="line" />
        </div>
        <div class="title">{{ step.title }}</div>
        <code v-if="step.code">{{ step.code }}</code>
        <p v-if="step.sub">{{ step.sub }}</p>
      </li>
    </ol>
    <figcaption v-if="caption">{{ caption }}</figcaption>
  </figure>
</template>

<style scoped>
.flow {
  margin: 28px 0;
  padding: 22px 22px 20px;
  border: 1px solid var(--k-border);
  border-radius: var(--k-radius);
  background: var(--k-bg);
}
ol {
  list-style: none;
  margin: 0;
  padding: 0;
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
  gap: 22px 18px;
}
li { margin: 0; min-width: 0; }
.head {
  display: flex;
  align-items: center;
  gap: 10px;
}
.n {
  font-family: var(--vp-font-family-mono);
  font-size: 11.5px;
  color: var(--k-accent);
}
.line {
  flex: 1;
  height: 1px;
  background: var(--k-border-strong);
}
li:last-child .line { background: linear-gradient(90deg, var(--k-border-strong), transparent); }
.title {
  margin-top: 12px;
  font-weight: 600;
  font-size: 14.5px;
  letter-spacing: -0.01em;
  color: var(--k-text);
}
code {
  display: inline-block;
  margin-top: 8px;
  font-family: var(--vp-font-family-mono);
  font-size: 11.5px;
  color: var(--k-text-2);
  border: 1px solid var(--k-border);
  border-radius: 5px;
  padding: 1px 6px;
  background: var(--k-surface);
  max-width: 100%;
  overflow-wrap: anywhere;
}
p {
  margin: 8px 0 0 !important;
  font-size: 13px !important;
  line-height: 1.55 !important;
  color: var(--k-text-2);
}
figcaption {
  margin-top: 18px;
  padding-top: 12px;
  border-top: 1px solid var(--k-border);
  font-size: 12.5px;
  color: var(--k-text-3);
}
</style>

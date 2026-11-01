<script setup lang="ts">
const items = [
  { id: 'live', title: 'Live pages', text: 'A GET marked [@@live] reloads every open page after a commit touches its tables.', link: '/data/live' },
  { id: 'tx', title: 'Transactions', text: 'Ok commits, Error rolls back. Services join the open connection without passing it.', link: '/data/transactions' },
  { id: 'jobs', title: 'Background jobs', text: 'Typed queues in your database, retries with backoff, enqueued inside the transaction.', link: '/background/jobs' },
  { id: 'flow', title: 'Workflows', text: 'States are constructors and transitions are patterns, so a typo stops the build.', link: '/data/workflow' },
  { id: 'router', title: 'Typed router', text: 'Routes are values. Links, params and query strings are checked by the compiler.', link: '/client/client-router' },
  { id: 'versions', title: 'Versions', text: 'A [@version] column makes a stale write change nothing, and the service answers 409.', link: '/data/database' },
  { id: 'profiler', title: 'Profiler', text: 'Every request with its SQL, and a flag when one query repeats in a loop.', link: '/tooling/observability' },
  { id: 'cli', title: 'Commands', text: 'A function with [@@command] runs from the same binary, with the same providers.', link: '/background/commands' }
]
</script>

<template>
  <div class="caps">
    <a v-for="item in items" :key="item.id" class="cap" :href="item.link">
      <div class="art">
        <!-- live: two windows, one write, one refresh -->
        <svg v-if="item.id === 'live'" viewBox="0 0 220 120" fill="none">
          <rect x="14" y="20" width="80" height="62" rx="6" class="s" />
          <path d="M14 32h80" class="s" />
          <rect x="24" y="42" width="44" height="6" rx="2" class="f" />
          <rect x="24" y="54" width="60" height="6" rx="2" class="f" />
          <rect x="24" y="66" width="34" height="6" rx="2" class="a" />
          <rect x="126" y="38" width="80" height="62" rx="6" class="s" />
          <path d="M126 50h80" class="s" />
          <rect x="136" y="60" width="44" height="6" rx="2" class="f" />
          <rect x="136" y="72" width="60" height="6" rx="2" class="f" />
          <rect x="136" y="84" width="34" height="6" rx="2" class="a" />
          <path d="M94 69c14 0 18 12 32 12" class="d" />
          <circle cx="110" cy="75" r="3" class="ad" />
        </svg>
        <!-- transactions: rows inside a bracket, commit or rollback -->
        <svg v-else-if="item.id === 'tx'" viewBox="0 0 220 120" fill="none">
          <path d="M40 18h-10v84h10" class="s" />
          <rect x="48" y="26" width="72" height="14" rx="3" class="s" />
          <rect x="48" y="53" width="72" height="14" rx="3" class="s" />
          <rect x="48" y="80" width="72" height="14" rx="3" class="s" />
          <path d="M130 60h22" class="s" />
          <path d="M152 60c10 0 10-22 22-22h18" class="s" />
          <path d="M152 60c10 0 10 22 22 22h18" class="d" />
          <circle cx="194" cy="38" r="4" class="ad" />
          <circle cx="194" cy="82" r="4" class="ring" />
          <text x="166" y="30" class="t">commit</text>
          <text x="166" y="100" class="t">rollback</text>
        </svg>
        <!-- jobs: a queue feeding a worker with a retry loop -->
        <svg v-else-if="item.id === 'jobs'" viewBox="0 0 220 120" fill="none">
          <rect x="16" y="48" width="22" height="22" rx="4" class="s" />
          <rect x="44" y="48" width="22" height="22" rx="4" class="s" />
          <rect x="72" y="48" width="22" height="22" rx="4" class="a" />
          <path d="M98 59h30" class="s" />
          <path d="M122 54l6 5-6 5" class="s" />
          <rect x="132" y="40" width="58" height="38" rx="6" class="s" />
          <circle cx="151" cy="59" r="4" class="ad" />
          <path d="M161 59h18" class="s" />
          <path d="M161 40c0-18-80-20-80 4" class="d" />
          <path d="M77 40l4 5 4-5" class="s" />
          <text x="102" y="20" class="t">retry 2s · 4s · 8s</text>
        </svg>
        <!-- workflow: states and allowed transitions -->
        <svg v-else-if="item.id === 'flow'" viewBox="0 0 220 120" fill="none">
          <rect x="12" y="46" width="44" height="24" rx="12" class="s" />
          <rect x="88" y="20" width="44" height="24" rx="12" class="s" />
          <rect x="88" y="76" width="44" height="24" rx="12" class="s" />
          <rect x="164" y="20" width="46" height="24" rx="12" class="a" />
          <path d="M56 54c14-14 18-22 32-22" class="s" />
          <path d="M56 62c14 14 18 26 32 26" class="s" />
          <path d="M132 32h32" class="s" />
          <path d="M110 44v32" class="d" />
          <circle cx="34" cy="58" r="3" class="ad" />
        </svg>
        <!-- router: a URL with typed segments -->
        <svg v-else-if="item.id === 'router'" viewBox="0 0 220 120" fill="none">
          <rect x="14" y="40" width="192" height="30" rx="15" class="s" />
          <text x="30" y="60" class="u">/cats/</text>
          <rect x="74" y="47" width="30" height="16" rx="4" class="a" />
          <text x="80" y="59" class="u2">:id</text>
          <text x="110" y="60" class="u">?breed=</text>
          <rect x="160" y="47" width="36" height="16" rx="4" class="s" />
          <path d="M89 70v18" class="d" />
          <text x="66" y="102" class="t">Cat.Id.t</text>
          <path d="M178 70v18" class="d" />
          <text x="148" y="102" class="t">Breed.t option</text>
        </svg>
        <!-- versions: one write wins, the stale one is refused -->
        <svg v-else-if="item.id === 'versions'" viewBox="0 0 220 120" fill="none">
          <rect x="10" y="46" width="74" height="28" rx="5" class="s" />
          <text x="21" y="64" class="u">cat · v3</text>
          <path d="M84 54c22 0 26-26 48-26" class="s" />
          <path d="M127 23l6 5-6 5" class="s" />
          <rect x="136" y="14" width="66" height="28" rx="5" class="a" />
          <text x="150" y="32" class="u2">cat · v4</text>
          <path d="M84 66c22 0 26 26 48 26" class="d" />
          <rect x="136" y="78" width="66" height="28" rx="5" class="s" />
          <text x="150" y="96" class="u">409</text>
          <path d="M184 85l10 14M194 85l-10 14" class="s" />
        </svg>
        <!-- profiler: requests as bars, one repeated query flagged -->
        <svg v-else-if="item.id === 'profiler'" viewBox="0 0 220 120" fill="none">
          <path d="M24 98h176" class="s" />
          <rect x="34" y="70" width="14" height="28" rx="2" class="f" />
          <rect x="58" y="56" width="14" height="42" rx="2" class="f" />
          <rect x="82" y="78" width="14" height="20" rx="2" class="f" />
          <rect x="106" y="30" width="14" height="68" rx="2" class="a" />
          <rect x="130" y="64" width="14" height="34" rx="2" class="f" />
          <rect x="154" y="74" width="14" height="24" rx="2" class="f" />
          <path d="M113 24v-8h44" class="d" />
          <text x="160" y="19" class="t">N+1</text>
        </svg>
        <!-- commands: a terminal -->
        <svg v-else viewBox="0 0 220 120" fill="none">
          <rect x="22" y="16" width="176" height="88" rx="8" class="s" />
          <circle cx="36" cy="28" r="3" class="ring" />
          <circle cx="46" cy="28" r="3" class="ring" />
          <circle cx="56" cy="28" r="3" class="ring" />
          <path d="M22 40h176" class="s" />
          <text x="34" y="60" class="u"><tspan class="acc">$</tspan> main.exe seed</text>
          <text x="34" y="78" class="u">  --count 3</text>
          <rect x="34" y="86" width="8" height="10" class="a" />
        </svg>
      </div>
      <div class="title">{{ item.title }}</div>
      <div class="text">{{ item.text }}</div>
    </a>
  </div>
</template>

<style scoped>
.caps {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  border: 1px solid var(--k-border);
  border-radius: 12px;
  overflow: hidden;
}
.cap {
  display: block;
  padding: 18px 20px 24px;
  text-decoration: none;
  border-right: 1px solid var(--k-border);
  border-bottom: 1px solid var(--k-border);
  background: var(--k-bg);
  transition: background 0.2s;
}
.cap:nth-child(4n) { border-right: none; }
.cap:nth-last-child(-n + 4) { border-bottom: none; }
.cap:hover { background: var(--k-surface); }
.art {
  height: 120px;
  margin: 0 -6px 16px;
  border-radius: 8px;
  background-image: radial-gradient(var(--k-dots) 1px, transparent 1px);
  background-size: 14px 14px;
}
svg { width: 100%; height: 100%; }
.s { stroke: var(--k-text-3); stroke-width: 1.2; }
.d { stroke: var(--k-text-3); stroke-width: 1.2; stroke-dasharray: 3 4; }
.f { fill: var(--k-border-strong); }
.a { fill: var(--k-accent); }
.aw { fill: var(--k-accent-soft); }
.ad { fill: var(--k-accent); }
.ring { stroke: var(--k-text-3); stroke-width: 1.2; fill: var(--k-bg); }
.t { font: 10px var(--vp-font-family-mono); fill: var(--k-text-3); }
.u { font: 11.5px var(--vp-font-family-mono); fill: var(--k-text-2); }
.u2 { font: 10.5px var(--vp-font-family-mono); fill: #fff; }
.acc { fill: var(--k-accent); }
.cap:hover .d { animation: dash 1.2s linear infinite; }
@keyframes dash { to { stroke-dashoffset: -14; } }
.title {
  font-weight: 600;
  font-size: 15px;
  letter-spacing: -0.015em;
  color: var(--k-text);
}
.text {
  margin-top: 6px;
  font-size: 13.5px;
  line-height: 1.55;
  color: var(--k-text-2);
}
@media (max-width: 1000px) {
  .caps { grid-template-columns: repeat(2, 1fr); }
  .cap:nth-child(4n) { border-right: 1px solid var(--k-border); }
  .cap:nth-child(2n) { border-right: none; }
  .cap:nth-last-child(-n + 4) { border-bottom: 1px solid var(--k-border); }
  .cap:nth-last-child(-n + 2) { border-bottom: none; }
}
@media (max-width: 560px) {
  .caps { grid-template-columns: 1fr; }
  .cap { border-right: none !important; border-bottom: 1px solid var(--k-border) !important; }
}
</style>

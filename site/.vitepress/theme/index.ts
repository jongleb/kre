import DefaultTheme from 'vitepress/theme'
import type { Theme } from 'vitepress'
import './custom.css'
import TypeFanout from './components/TypeFanout.vue'
import RequestPipeline from './components/RequestPipeline.vue'
import CompileVsRuntime from './components/CompileVsRuntime.vue'
import StatGrid from './components/StatGrid.vue'
import Layers from './components/Layers.vue'
import Flow from './components/Flow.vue'
import Home from './components/Home.vue'

export default {
  extends: DefaultTheme,
  enhanceApp({ app }) {
    app.component('TypeFanout', TypeFanout)
    app.component('RequestPipeline', RequestPipeline)
    app.component('CompileVsRuntime', CompileVsRuntime)
    app.component('StatGrid', StatGrid)
    app.component('Layers', Layers)
    app.component('Flow', Flow)
    app.component('Home', Home)
  }
} satisfies Theme

import { defineConfig } from 'vitepress'
import { withMermaid } from 'vitepress-plugin-mermaid'
import { attributes } from './attributes'

export default withMermaid(
  defineConfig({
    title: 'Kre',
    description:
      'Kre is a typed full-stack web framework for OCaml: one type for the table, the JSON, the API docs and the browser.',
    appearance: 'dark',
    cleanUrls: true,
    lastUpdated: false,
    head: [
      ['link', { rel: 'icon', href: '/logo.svg' }],
      ['link', { rel: 'preconnect', href: 'https://fonts.googleapis.com' }],
      ['link', { rel: 'preconnect', href: 'https://fonts.gstatic.com', crossorigin: '' }],
      [
        'link',
        {
          rel: 'stylesheet',
          href: 'https://fonts.googleapis.com/css2?family=Geist:wght@400;500;600;700&family=Geist+Mono:wght@400;500&display=swap'
        }
      ]
    ],
    markdown: {
      theme: { light: 'vitesse-light', dark: 'vitesse-dark' },
      languageAlias: { ml: 'ocaml', mli: 'ocaml', mlx: 'ocaml', dune: 'scheme' },
      codeTransformers: [attributes]
    },
    themeConfig: {
      logo: { light: '/logo-light.svg', dark: '/logo-dark.svg' },
      siteTitle: 'kre',
      nav: [
        { text: 'Guide', link: '/guide/introduction' },
        { text: 'Data', link: '/data/database' },
        { text: 'Client', link: '/client/client-router' },
        { text: 'Shelter tour', link: '/reference/shelter' }
      ],
      sidebar: [
        {
          text: 'Start here',
          items: [
            { text: 'Introduction', link: '/guide/introduction' },
            { text: 'Getting started', link: '/guide/getting-started' },
            { text: 'Architecture', link: '/guide/architecture' }
          ]
        },
        {
          text: 'Fundamentals',
          items: [
            { text: 'Controllers', link: '/guide/controllers' },
            { text: 'Dependency injection', link: '/guide/dependency-injection' },
            { text: 'Validation & types', link: '/guide/validation' },
            { text: 'Guards & auth', link: '/guide/guards-auth' },
            { text: 'Errors & interceptors', link: '/guide/errors' }
          ]
        },
        {
          text: 'Data',
          items: [
            { text: 'Tables & SQL', link: '/data/database' },
            { text: 'Transactions', link: '/data/transactions' },
            { text: 'Migrations', link: '/data/migrations' },
            { text: 'Live loaders', link: '/data/live' },
            { text: 'Workflows', link: '/data/workflow' }
          ]
        },
        {
          text: 'Beyond requests',
          items: [
            { text: 'Background jobs', link: '/background/jobs' },
            { text: 'Commands', link: '/background/commands' },
            { text: 'Schedules & events', link: '/background/schedule-events' },
            { text: 'Mail', link: '/background/mail' }
          ]
        },
        {
          text: 'Client',
          items: [
            { text: 'Typed client & router', link: '/client/client-router' },
            { text: 'Pages in mlx', link: '/client/pages' },
            { text: 'Calling other APIs', link: '/client/http-client' }
          ]
        },
        {
          text: 'Tooling',
          items: [
            { text: 'Testing', link: '/tooling/testing' },
            { text: 'Actuator & profiler', link: '/tooling/observability' },
            { text: 'CLI & OpenAPI', link: '/tooling/cli' }
          ]
        },
        {
          text: 'Reference',
          items: [
            { text: 'Shelter: a full app', link: '/reference/shelter' }
          ]
        }
      ],
      socialLinks: [{ icon: 'github', link: 'https://github.com/jongleber/kre' }],
      search: { provider: 'local' },
      outline: { level: [2, 3], label: 'On this page' },
      footer: {
        message: 'Functions, modules, functors and ppx. No classes, no reflection, no runtime container.',
        copyright: 'Kre — ISC License'
      }
    }
  }),
  {
    mermaid: {
      theme: 'base',
      themeVariables: {
        darkMode: true,
        background: '#0f0f11',
        fontFamily: 'Geist, ui-sans-serif, system-ui',
        fontSize: '14px',
        primaryColor: '#17171a',
        primaryTextColor: '#ededef',
        primaryBorderColor: '#3a3a40',
        secondaryColor: '#17171a',
        secondaryBorderColor: '#3a3a40',
        tertiaryColor: '#121214',
        tertiaryBorderColor: '#2a2a2e',
        lineColor: '#6b6b73',
        textColor: '#a1a1aa',
        mainBkg: '#17171a',
        clusterBkg: '#121214',
        clusterBorder: '#2a2a2e',
        nodeBorder: '#3a3a40',
        noteBkgColor: '#1d1612',
        noteTextColor: '#ffb4a1',
        noteBorderColor: '#ff6b4a',
        actorBkg: '#17171a',
        actorBorder: '#3a3a40',
        actorTextColor: '#ededef',
        actorLineColor: '#3a3a40',
        signalColor: '#a1a1aa',
        signalTextColor: '#ededef',
        labelBoxBkgColor: '#17171a',
        labelBoxBorderColor: '#3a3a40',
        labelTextColor: '#ededef',
        loopTextColor: '#a1a1aa',
        activationBkgColor: '#26262b',
        activationBorderColor: '#ff6b4a',
        edgeLabelBackground: '#0f0f11',
        attributeBackgroundColorOdd: '#17171a',
        attributeBackgroundColorEven: '#121214'
      }
    }
  }
)

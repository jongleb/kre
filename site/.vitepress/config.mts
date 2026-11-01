import { defineConfig } from 'vitepress'
import { withMermaid } from 'vitepress-plugin-mermaid'

export default withMermaid(
  defineConfig({
    title: 'Kre',
    description:
      'A typed full-stack framework for OCaml: Nest structure, Spring power, Rails speed — checked by the compiler.',
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
          href: 'https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800;900&family=JetBrains+Mono:wght@400;500;700&display=swap'
        }
      ]
    ],
    markdown: {
      theme: { light: 'github-light', dark: 'one-dark-pro' },
      languageAlias: { ml: 'ocaml', mli: 'ocaml', mlx: 'ocaml', dune: 'scheme' }
    },
    themeConfig: {
      logo: '/logo.svg',
      siteTitle: 'Kre',
      nav: [
        { text: 'Guide', link: '/guide/introduction' },
        { text: 'Data', link: '/data/database' },
        { text: 'Client', link: '/client/client-router' },
        { text: 'Borrowed', link: '/reference/borrowed' },
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
            { text: 'What we borrowed', link: '/reference/borrowed' },
            { text: 'Shelter: a full app', link: '/reference/shelter' }
          ]
        }
      ],
      socialLinks: [{ icon: 'github', link: 'https://github.com/jongleber/forge' }],
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
        background: '#151922',
        fontFamily: 'Inter, ui-sans-serif, system-ui',
        primaryColor: '#1f2533',
        primaryTextColor: '#e9edf5',
        primaryBorderColor: '#ff7a18',
        secondaryColor: '#241b2f',
        secondaryBorderColor: '#9b5de5',
        tertiaryColor: '#14231d',
        tertiaryBorderColor: '#3ddc97',
        lineColor: '#ff9a3c',
        textColor: '#c9d1e0',
        noteBkgColor: '#2a2216',
        noteTextColor: '#ffd9a8',
        noteBorderColor: '#ffc24b',
        actorBkg: '#1f2533',
        actorBorder: '#ff7a18',
        actorTextColor: '#e9edf5',
        signalColor: '#ff9a3c',
        signalTextColor: '#e9edf5',
        labelBoxBkgColor: '#1f2533',
        labelTextColor: '#e9edf5',
        edgeLabelBackground: '#151922'
      }
    }
  }
)

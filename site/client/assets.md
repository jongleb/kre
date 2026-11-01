# Assets & icons

<p class="lead">Static files are referenced through the compiler. <code>[%asset "logo.svg"]</code> fails the build when the file is missing, and gives you a URL that changes whenever the file does, so browsers can cache it forever.</p>

<Flow :steps="[
  { title: 'You write', code: '[%asset &quot;logo.svg&quot;]', sub: 'In any server or browser code' },
  { title: 'kre-ppx reads', code: 'assets/logo.svg', sub: 'At build time, next to your app' },
  { title: 'You get', code: '/assets/logo.a22b3af5.svg', sub: 'The content hash is in the URL' },
  { title: 'The server sends', code: 'immutable', sub: 'Cached for a year, never stale' }
]" />

## Files

Put static files in an `assets/` folder at the root of the application, next to `server/` and `client/`. Reference them with `[%asset]`:

```ocaml
<img src=(Kre_shared.Asset.url [%asset "logo.svg"]) alt="Shelter" />
```

The value is a `Kre_shared.Asset.t`, not a string. Only `[%asset]` makes one, so a function that takes an asset cannot be handed a typo. A misspelled name stops the build and suggests the closest file:

```text
Error: assets/sight.css does not exist (did you mean "site.css"?);
add the file and list the folder in (preprocessor_deps (source_tree ../assets))
```

The URL carries the first eight characters of the file's MD5: `/assets/logo.a22b3af5.svg`. Edit the file and every reference gets a new URL on the next build.

## Icons

`[%icon "cat"]` reads `assets/icons/cat.svg` and embeds the drawing in the program, so an icon needs no request at all. A missing file or a file without an `<svg>` element is a compile error. In the browser, draw it with `Kre_client.Icon.view`:

```ocaml
<li>(Kre_client.Icon.view [%icon "cat"]) (React.string name)</li>
```

The icon is rendered inside a `span` with `role="img"` and its name as the label, and it takes the text colour of its surroundings when the SVG uses `currentColor`.

## Serving

`Kre.Assets.middleware ~dir` answers `GET /assets/…` from the folder:

<<< @/../examples/shelter/bin/main.ml

| Request | Answer |
| --- | --- |
| `/assets/logo.a22b3af5.svg`, hash matches the file | `200`, `Cache-Control: public, max-age=31536000, immutable` |
| `/assets/logo.deadbeef.svg`, an old or wrong hash | `404`, never an outdated file under a new name |
| `/assets/../config.ml` | `404` |

## Build setup

The ppx reads the folder while compiling, so tell dune about it; then changing a file rebuilds the code that references it:

<<< @/../examples/shelter/client/dune{45-46}

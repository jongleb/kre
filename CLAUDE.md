# Forge

NestJS-like full-stack framework in OCaml 5.5: Dream on the server, Melange on
the client. `DESIGN.md` is the source of truth: the plan, the target `.mli`s,
the phases. Read the relevant section before implementing it.

## Setup

```sh
opam switch create . 5.5.1 --deps-only --with-test   # local switch in _opam/
eval $(opam env --switch=. --set-switch)
dune build @all && dune test && dune build @fmt
```

## Layout

- `src/shared` — `Forge_shared` (Validation, Json, Scalar, Refined), built twice:
  native (`forge.shared`) and Melange (`src/shared/melange`,
  `forge-client.shared`) from the same sources via `copy_files#`.
- `src/core` — `Forge` server runtime (Error, Response, Guard, Spec, Route,
  Controller, App).
- `src/ppx`, `src/client`, `src/cli` — phase 1.
- `test/core` — alcotest; `test/ppx` — expect tests; `test/e2e` — phase 1.

## Process

- One row of a phase table = one commit with tests. Phases in order.
- If the design does not fit reality (a library version, a ppx limitation),
  edit `DESIGN.md` with the reason first, then the code.
- Do not widen a phase: new ideas go to "Открытые вопросы" in `DESIGN.md`.

## Code

- Follow the global `ocaml-design` rules: illegal states unrepresentable,
  parse don't validate, no boolean blindness, no aliases of any kind, no
  single-use top-level helpers, option combinators over `match`, comments only
  on types/constructors/fields/modules.
- Every public module has an `.mli`; `Forge.*` signatures are exactly those in
  `DESIGN.md` → "Forge.Core". Changing one means editing that section in the
  same commit.
- No `assert false`, no `failwith` in library code, no `Obj.magic`.
- Dream is not wrapped: `Dream.request`, `Dream.middleware`, `Dream.response`
  belong in Forge signatures.
- Generated ppx code only calls `Forge.Route` / `Forge_shared.*`; logic lives in
  the runtime where it can be tested without the ppx.
- ppx errors: `Location.raise_errorf` on the offending node, text "what is
  wrong → what to do". Generated names start with `__forge_`.
- ocamlformat 0.29, profile `default`; CI fails on unformatted code.

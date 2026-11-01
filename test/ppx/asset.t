[%asset "file"] and [%icon "name"] look into the application's assets/
folder (next to the folder of the source file) at build time.

  $ mkdir -p app/client app/assets/icons
  $ printf 'body {}' > app/assets/site.css
  $ printf '<?xml version="1.0"?>\n<svg viewBox="0 0 1 1"><path d="M0 0h1"/></svg>\n' > app/assets/icons/cat.svg
  $ printf 'not a drawing' > app/assets/icons/broken.svg
  $ cat > app/client/page.ml <<'ML'
  > let style = [%asset "site.css"]
  > let cat = [%icon "cat"]
  > ML
  $ ./pp.exe -impl app/client/page.ml
  let style = Kre_shared.Asset.checked "/assets/site.fcdce6b6.css"
  let cat =
    Kre_shared.Icon.checked ~name:"cat"
      "<svg viewBox=\"0 0 1 1\"><path d=\"M0 0h1\"/></svg>"

A missing file is a compile error, with the closest name as a hint.

  $ cat > app/client/page.ml <<'ML'
  > let style = [%asset "sight.css"]
  > ML
  $ ./pp.exe -impl app/client/page.ml
  File "app/client/page.ml", line 1, characters 12-32:
  1 | let style = [%asset "sight.css"]
                  ^^^^^^^^^^^^^^^^^^^^
  Error: assets/sight.css does not exist (did you mean "site.css"?); add the file and list the folder in (preprocessor_deps (source_tree ../assets))
  [1]
  $ cat > app/client/page.ml <<'ML'
  > let dog = [%icon "dog"]
  > ML
  $ ./pp.exe -impl app/client/page.ml
  File "app/client/page.ml", line 1, characters 10-23:
  1 | let dog = [%icon "dog"]
                ^^^^^^^^^^^^^
  Error: assets/icons/dog.svg does not exist; add the file and list the folder in (preprocessor_deps (source_tree ../assets))
  [1]
  $ cat > app/client/page.ml <<'ML'
  > let broken = [%icon "broken"]
  > ML
  $ ./pp.exe -impl app/client/page.ml
  File "app/client/page.ml", line 1, characters 13-29:
  1 | let broken = [%icon "broken"]
                   ^^^^^^^^^^^^^^^^
  Error: assets/icons/broken.svg is not an SVG: it has no <svg> element
  [1]

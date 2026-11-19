# Agent-Driven Development Showcases

<!-- This page surfaces the repo-root showcase catalog (dx-agent-dev-showcase/README.md)
     in the docs site via include-markdown. The catalog is generated from
     dx-agent-dev-showcase/showcases.json by `dx-showcase-gen regen-docs`, so there is a
     single source of truth — do NOT hand-edit the included content here. docs/mkdocs.sh
     stages the catalog as docs/_showcase_catalog.md and copies its media (repo-root img/)
     into source/img/ for the build; rewrite-relative-urls (on by default) then resolves
     the image paths for the rendered site. -->

{%
   include-markdown "../_showcase_catalog.md"
   rewrite-relative-urls=true
   heading-offset=1
%}

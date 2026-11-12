# kora_garages agent guide

`kora_garages` is the Kora player garage resource: store and retrieve owned vehicles, job and gang fleets, an impound lot with a fee, and runtime property garages registered by other resources. Layout: `fxmanifest.lua`, `shared/config.lua` (config), `client/client.lua` (zones, blips, markers, NUI app, take-out/store flow), `client/compat.lua` (qb-garages no-op events), `server/server.lua` (list/take-out/store authority, `garage:storeAll`), `server/property.lua` (property garage exports and persistence), `server/schema.lua`, `server/compat.lua` (qb-garages shims), `test/` (offline Lua tests) and `tests/` (kora_qa feature files).

## Documentation

User-facing documentation lives in `docs/` (Markdown, published via the Kora Docusaurus site, kora_docs_next). Read `docs/index.md` first (hub with a documentation map). Layout: `installation.md` (dependencies, manifest, schema, setup), `how-to-use.md` (store/take-out/impound/property flows and detailed behaviour), `commands.md` (`garage:storeAll`), `api/` (`index.md` plus `exports.md`, server and client exports), and topic pages `configuration.md`, `events.md`, `database.md`, `compatibility.md`, `testing.md`, `troubleshooting.md`. Update the page that owns the topic.

Feature and behaviour changes must update the matching docs in the same change.

When you add, change, or remove a feature, config option, command, export, event, item, permission, or database table/column, update the matching page in `docs/` in the same change. Keep docs accurate to the code; do not document behaviour that does not exist.

Docs rules: plain Markdown with `title`/`sidebar_position` front matter (no `id`/`slug`), relative links only between docs pages, assets inside `docs/`, fenced code blocks with a language, and no raw `<`, `>`, `{`, `}` outside code (pages are parsed as MDX). The release version comes from `fxmanifest.lua`'s `version` field.

## Shared contribution standards

Read [CONTRIBUTING.md](CONTRIBUTING.md) before editing. Humans and agents follow
the same Kora standards and self-contained local Lua checks. Preserve the domain
constraints above and in module guides; record policy conflicts explicitly.

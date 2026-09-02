# 「发明」河图洛书 · Invent the Lo Shu

An interactive three-act game in which you *invent* the Lo Shu magic square —
first a language of marks, then the arithmetic of ten, then the moment the
language you built runs out.

Playable in **繁體中文（香港）· 简体中文 · English**, and installable as an app
on phone and desktop.

## Play

Open the deployed page (GitHub Pages). On phone, use your browser's
**Add to Home Screen**; on desktop Chrome/Edge, use the **Install** button in
the header or the install icon in the address bar. Once installed it runs
offline.

## Languages

The switch in the header (繁 / 简 / EN) changes every string at runtime and
remembers your choice in `localStorage`. All three locale tables carry the same
226 keys; the 繁體 table is generated from the 简体 source with OpenCC (`s2hk`,
Hong Kong character standard).

## Files

```
index.html             the whole game — markup, styles, logic, all three locales
manifest.webmanifest   PWA manifest (standalone display, icons, theme)
sw.js                  service worker — app-shell cache, offline play
icons/                 192/512 icons, maskable variants, apple-touch-icon
.nojekyll              tell GitHub Pages to serve the tree as-is
```

## Local development

The service worker needs a real origin, so open it over HTTP rather than
`file://`:

```sh
python3 -m http.server 8000
# then visit http://localhost:8000/
```

Bumping `VERSION` in `sw.js` invalidates the old cache on the next visit.

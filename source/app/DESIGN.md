# DNS Bench for macOS — design & engineering contract

This file is the contract between the main process, the renderer, and anyone (human or
agent) touching the app. Keep it in sync when you add a screen, an IPC call, or a
shared component.

## Toolchain

This machine has **Command Line Tools only** (no Xcode, no SwiftUI SDK). The app is an
Electron shell with a native macOS window and a hand-built HTML/CSS/JS interface.

- Native window: `titleBarStyle: "hiddenInset"`, `vibrancy: "under-window"`,
  `visualEffectState: "active"`, `trafficLightPosition`, forced dark appearance.
- The UI must read as a native macOS app, not a web page: SF Pro, 8pt grid, compact
  rows, layered glass, 180–420ms motion, keyboard support.
- Only `source/app/**` and `source/scripts/**` are versioned. `node_modules`,
  `build/`, `dist/`, `*.app` stay on the machine.

## File map

```
source/
  app/
    package.json
    main.js                 window, menu, tray, IPC, history, CSV, screenshot modes
    preload.js              contextBridge API (window.dnsBench)
    main/engine.js          resolver list, probes, network info, DNS apply/reset
    main/platform.js        child_process / osascript / TCP helpers
    renderer/index.html     shell
    renderer/app.js         state, events, IPC wiring, shortcuts
    renderer/views.js       pure render functions -> HTML strings
    renderer/styles.css     design system + layout + motion
    renderer/icons.js       inline SVG icon set (window.Icons)
    resources/icon.svg      icon source (build script renders the .icns)
  scripts/
    build.sh                npm install, icon, .app packaging, ad-hoc sign
    run.sh                  build if needed, open the app
    dev.sh                  electron . in dev mode
    make-icon.js            pure-Node PNG renderer for the app + tray icons
  (ignore rules live in the repo-root .gitignore)
```

## State (renderer)

```js
{
  screen: 'overview' | 'benchmark' | 'network' | 'history' | 'settings',
  status: 'idle' | 'running' | 'done' | 'error',
  resolvers: Resolver[],
  results: ProbeResult[],
  network: Network | null,
  history: Run[],
  progress: { done: number, total: number, label: string, phase: string },
  best: ProbeResult | null,
  selected: number | null,          // resolver index
  filter: 'all' | 'U' | 'F' | 'A' | 'C',
  search: string,
  sort: { key: 'score'|'cached'|'cold'|'loss'|'name', dir: 'asc'|'desc' },
  settings: { samples, domain, concurrency, autoExport, v6 },
  error: string | null,
  startedAt: number | null,
  durationMs: number | null
}
```

```ts
type Resolver = { index, name, kind: 'U'|'F'|'A'|'C', region, v4: string[], v6: string[] }
type ProbeResult = {
  index, name, kind, region,
  cached: number|'Timeout', jitter: number|null, loss: number,
  cold: number|null, score: number|'—',
  v4ping: number|null, v6dns: number|'N/A'|'Timeout', v6ping: number|null,
  dnssec: 'yes'|'no'|'?', nx: 'ok'|'HIJACK'|'?',
  tcp: 'yes'|'no'|'?', dot: 'yes'|'no'|'?', doh: 'yes'|'no'|'?',
  ads: 'yes'|'no'|'?', pop: string,
  servers: string[]
}
type Network = {
  host, os, arch, interface, service, link, mac, mtu,
  localIPv4, localIPv6: string[], gateway, gatewayMs, gatewayLoss,
  publicIP, publicIP6, isp, asn, location, timezone, pop, warp,
  dnsInUse: string[], dnsSource, vpn, proxy, v6: boolean,
  wifi, captive, intercept, egress
}
type Run = { id, at, best, score, count, durationMs, rows: ProbeResult[] }
```

## IPC

`preload.js` exposes `window.dnsBench`:

| method | returns |
|---|---|
| `init()` | `{ resolvers, network, history, settings, version }` |
| `runBenchmark(opts)` | `{ ok, cancelled? }` — streams events below |
| `cancelBenchmark()` | `{ ok }` |
| `applyResolver(index)` | `{ ok, message, servers }` |
| `resetDNS()` | `{ ok, message }` |
| `dnsStatus()` | `{ mode, servers, service }` |
| `exportCSV(rows)` | `{ ok, path?, cancelled? }` |
| `openResultsFolder()` | `{ ok }` |
| `saveSettings(settings)` | `{ ok }` |

Events (`onX(cb)`):

| event | payload |
|---|---|
| `benchmark:progress` | `{ done, total, label, phase }` |
| `benchmark:result` | `ProbeResult` |
| `benchmark:done` | `{ rows, best, durationMs, csvPath }` |
| `benchmark:error` | `{ message }` |
| `app:navigate` | screen name (from the tray menu) |
| `app:command` | `run` / `cancel` / `apply-best` / `reset` / `export` (menu bar + tray) |

## View contract (`renderer/views.js`)

Every function is pure and returns an HTML string. Escape untrusted text with
`Views.esc()`. Numeric formatting lives in `Views.fmtMs`, `Views.fmtScore`.

```js
window.Views = {
  esc(value): string,
  fmtMs(value, opts): string,
  fmtScore(value): string,
  sidebar(state): string,
  topbar(state): string,
  overview(state): string,
  benchmark(state): string,
  network(state): string,
  history(state): string,
  settings(state): string,
  inspector(state): string,
  benchTable(state): string,      // rows only, re-rendered on search/filter/sort/result
  benchCount(state): string,      // "42 resolvers · 5 samples" style summary
  progress(state): string,        // live progress block, re-rendered per progress event
  confirm(state, opts): string,   // opts = { title, message, confirmLabel, danger }
  empty(title, text, icon): string
}
```

Interactive elements carry `data-action` and optional `data-*` payloads. `app.js`
handles them by delegation:

`nav` (`data-screen`), `run`, `cancel`, `apply` (`data-index`), `reset`, `export`,
`select` (`data-index`), `filter` (`data-filter`), `sort` (`data-key`), `search`,
`open-results`, `settings` (`data-key`, `data-value`), `about`, `close-modal`,
`confirm-ok`, `confirm-cancel`, `refresh-network`, `clear-history`.

## CSS contract (`renderer/styles.css`)

Layout: `.app`, `.sidebar`, `.main`, `.topbar`, `.content`, `.inspector`, `.toasts`,
`.modal-backdrop`, `.modal`.

Components (all must be styled):

```
glass, glass-strong, glass-subtle, card, card-header, card-title, card-subtitle, card-body,
divider, sidebar-brand, brand-mark, brand-name, nav, nav-item, nav-item.active,
nav-icon, nav-label, nav-badge, sidebar-footer, status-pill, status-dot,
topbar-title, topbar-subtitle, topbar-actions, window-drag,
hero, hero-gauge, gauge-ring, gauge-value, gauge-label, hero-copy, hero-actions,
metric-grid, metric, metric-label, metric-value, metric-delta,
metric-good, metric-warn, metric-bad,
btn, btn-primary, btn-ghost, btn-danger, btn-sm, icon-btn, segmented, segmented-item,
segmented-item.active, chip, chip-U, chip-F, chip-A, chip-C, chip-good, chip-warn, chip-bad,
table, table-head, table-row, table-row.selected, cell, cell-name, cell-num, cell-sub,
bar, bar-fill, progress, progress-track, progress-fill, progress-label, progress-meta,
spinner, search, field, input, select, slider, switch,
empty, empty-icon, empty-title, empty-text,
list, list-row, list-row-title, list-row-meta, badge, kbd,
toast, toast.show, toast-good, toast-bad, toast-info,
modal-header, modal-body, modal-footer, about, about-logo, about-links,
chart, chart-row, chart-label, chart-track, chart-fill, chart-value,
fade-in, stagger, shimmer, pulse
```

Tokens (CSS custom properties on `:root`):

```css
--bg:#0b0d12; --bg-2:#0f1218;
--glass:rgba(255,255,255,.06); --glass-2:rgba(255,255,255,.09);
--stroke:rgba(255,255,255,.10); --stroke-2:rgba(255,255,255,.16);
--text:#f5f6f8; --text-2:rgba(235,238,245,.72); --text-3:rgba(235,238,245,.44);
--accent:#0a84ff; --green:#30d158; --yellow:#ffd60a; --orange:#ff9f0a;
--red:#ff453a; --purple:#bf5af2; --teal:#64d2ff;
--r-sm:12px; --r:18px; --r-lg:26px;
--spring:cubic-bezier(.22,1,.36,1);
--shadow:0 18px 50px rgba(0,0,0,.45);
--font:-apple-system,"SF Pro Display","SF Pro Text","Helvetica Neue",sans-serif;
--mono:"SF Mono",ui-monospace,Menlo,monospace;
```

Glass recipe: `backdrop-filter: blur(24px) saturate(180%)`, layered white gradient,
1px inner top highlight (`inset 0 1px 0 rgba(255,255,255,.14)`), soft outer shadow,
18px radius. Never put text directly on a busy background without a glass layer.

## Icon contract (`renderer/icons.js`)

```js
window.Icons = {
  logo(size): string,          // brand mark, gradient
  icon(name, size, className): string  // inline <svg>
}
```

Names: `gauge`, `list`, `globe`, `clock`, `gear`, `play`, `stop`, `export`, `refresh`,
`check`, `alert`, `chevron`, `search`, `shield`, `bolt`, `wifi`, `server`, `arrow-up-right`,
`x`, `info`, `external`, `trash`, `sparkles`, `lock`, `cpu`, `network`, `download`.
All icons: 24×24 viewBox, `fill="none"`, `stroke="currentColor"`, `stroke-width="1.7"`,
round caps/joins.

## Main-process contract (`main/engine.js`)

```js
module.exports = {
  RESOLVERS,                                   // static list without router/current
  buildResolvers(): Promise<{ resolvers, network }>,
  getNetworkInfo(): Promise<Network>,
  runBenchmark({ resolvers, samples, domain, concurrency, onProgress, onResult, isCancelled }): Promise<ProbeResult[]>,
  cancel(),
  applyResolver(resolver, { hasV6 }): Promise<{ ok, message, servers }>,
  resetDNS(): Promise<{ ok, message }>,
  getDnsStatus(): Promise<{ mode, servers, service }>
}
```

`main/platform.js`:

```js
module.exports = {
  run(cmd, args, opts): Promise<{ stdout, stderr, code }>,
  shell(command): Promise<{ stdout, stderr, code }>,
  adminShell(command): Promise<{ stdout, stderr, code }>, // osascript "with administrator privileges"
  tcpConnect(host, port, timeoutMs): Promise<number|null>, // milliseconds or null
  which(cmd): boolean
}
```

## Design intent per screen

- **Overview**: the “at a glance” screen. Big gauge with the best score, current DNS vs
  fastest resolver comparison, network summary cards, last run strip, primary
  “Run benchmark” action. No table.
- **Benchmark**: toolbar (filters, search, run/cancel, export), live progress, dense
  results table with inline latency bars, row selection drives the inspector.
- **Network**: identity card, gateway/public IP, DNS source, health checks (interception,
  captive portal, IPv6, VPN/proxy), continent latency chart.
- **History**: last 20 runs, each with time, best resolver, score and a sparkline; click
  to load that run into the benchmark screen.
- **Settings**: samples, domain, concurrency, auto-export, reset; About card with author
  Dharm Sharma and dharmsharma.com.
- **Inspector**: selected resolver detail — all metrics, feature chips, servers, Apply /
  copy buttons. Empty state when nothing is selected.
- **Tray**: quick actions (Open, Run, Apply best, Reset DNS) and a tiny status line.

## Verification

```sh
source/scripts/build.sh
source/scripts/run.sh
# visual check (writes a PNG and exits)
source/app/node_modules/.bin/electron source/app --screenshot=/tmp/dnsbench.png --screenshot-delay=2000
```

`main.js` must support `--screenshot=<path>` and `--screenshot-delay=<ms>` for this.


## Decisions that shape the UI

- **Who "wins"** — `Views.leaderRow()` only considers resolvers you can actually switch to
  (kind `U`) plus the baselines (`C`). Filtered/ad-block resolvers (`F`, `A`) win nothing on
  the overview; they are marked and listed in the benchmark table. This matches the CLI rule
  and avoids telling people to install a content filter they did not ask for.
- **Baselines are honest** — if your router or current resolver has the lowest score, the
  hero says so and offers the best *switchable* resolver instead of a misleading "X wins".
- **Screens** — the inspector exists only on Benchmark (`data-screen` CSS switches the grid
  to two columns elsewhere). Overview adds a compact ranked list (`rank-row`) that deep-links
  into Benchmark with the row preselected.
- **Selection** — after a run (or loading history) the lowest-score row is auto-selected so the
  inspector is never empty when data exists.
- **Tray** — rebuilt after each run so "Apply Best — <name>" reflects real results.

## Screenshot modes

```sh
electron . --screenshot=/tmp/x.png [--screenshot-delay=1800] [--screenshot-scroll=520] \
           [--screenshot-run] [--screenshot-screen=overview|benchmark|network|history|settings]
```

`--screenshot-run` clicks the visible Run button after load; `--screenshot-screen` navigates
first; `--screenshot-scroll` scrolls the content pane so lower cards can be captured. The window always shows (inactive) so `capturePage()` has pixels; the process exits
after writing the PNG.

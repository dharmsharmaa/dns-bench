# dns-bench

<img src="docs/screenshots/app-overview.png" alt="DNS Bench app, overview screen" width="820">

*the macOS app: best score, current DNS, and a ranked top-5 at a glance.*

Benchmark ~50 public DNS resolvers, inspect your network, troubleshoot a domain, and switch to the fastest resolver. macOS + Linux (`dns-bench.zsh`) and Windows (`dns-bench.ps1`). Current version: **v3.2.0**.

By **[Dharm Sharma](https://dharmsharma.com)** · MIT licensed, free to use.

## why i made this

Most "best DNS" lists are written from a datacenter somewhere else. The resolver that wins on a blog post is often not the one that is fastest from your couch, on your ISP, on your Wi-Fi. I wanted one command that answers the boring but useful questions:

- which resolver is actually fastest from *this* network right now?
- is my router or ISP hijacking DNS or rewriting NXDOMAIN?
- does the resolver validate DNSSEC, block ads, answer over TCP/DoT, and which anycast node do I land on?
- which resolver hands me the closest CDN edge for the sites I actually use?
- why does one domain fail while everything else works?

So `dns-bench` measures instead of guessing, shows you the numbers, and then optionally applies the winner (with a backup of your old settings). It is a single script with no install, no daemon, and no telemetry.

## what it can do

**Network info**
local IPs, gateway (+ latency), public IPv4/IPv6, ISP/ASN, location, VPN/proxy detection, DNS currently in use, nearest Cloudflare PoP, first few traceroute hops. Also checks for port-53 interception (router/ISP hijacking) and captive portals.

**DNS benchmark, per resolver**
cached and uncached latency, jitter, packet loss, IPv4/IPv6 ping, DNSSEC validation, NXDOMAIN hijacking, TCP/53, DoT:853, 443 reachability, a rough ad-block check, and which anycast PoP answers you.

**Continent latency**
TCP connect time to AWS regions on every continent. Shows how far you really are from things, independent of which DNS you pick.

**Popular services**
resolves ~30 sites (google, youtube, meta, netflix, hotstar, flipkart, github, npm, openai, anthropic, zoom, steam, cdns) through the top resolvers, then times a connect to the IP each one returned. The fastest lookup is not always the closest edge; this shows which resolver sends you somewhere near.

**Speed test**
latency, jitter, download and upload throughput with parallel streams and a live meter. Independent of which DNS you use, so you can tell whether a slow site is DNS or just the link.

**Domain troubleshooting**
`dns-bench test example.com` compares resolvers, prints records, checks authoritative name servers and SOA serials, DNSSEC, TCP/HTTPS reachability, and ends with a plain-English verdict.

**Progress + CSV**
a live progress bar while probing, and results are automatically saved as CSV next to the script (see below).

## screenshots

Everything below was captured in demo mode — fake IPs, `example.com`, and an invented ISP — so no real network, resolver timing, or history appears.

| | |
|---|---|
| <img src="docs/screenshots/app-overview.png" alt="app overview"> | <img src="docs/screenshots/app-benchmark.png" alt="app benchmark table"> |
| *overview — score gauge, current DNS, top 5* | *benchmark — every resolver, sortable, with Apply* |
| <img src="docs/screenshots/app-network.png" alt="app network screen"> | <img src="docs/screenshots/app-settings.png" alt="app settings screen"> |
| *network — identity, DNS source, health checks* | *settings — samples, domain, concurrency, results folder* |

<img src="docs/screenshots/cli-benchmark.png" alt="CLI benchmark output" width="820">

*cli — the benchmark table, ranked with cached/cold latency and feature columns.*

<img src="docs/screenshots/cli-speed.png" alt="CLI speed test output" width="820">

*cli — `speed`, independent of which DNS you use.*

<img src="docs/screenshots/cli-demo.png" alt="CLI demo output, full run" width="820">

*cli — the full `demo` run: network block, benchmark, features, regions, speed, summary.*

## demo mode

You do not need to trust a stranger's screenshot, and you do not need to expose your own network to take one. Both CLIs and the app have a demo mode that produces a full-looking run from hardcoded data.

```sh
./dns-bench.zsh demo          # macOS / Linux
.\dns-bench.ps1 demo          # Windows
source/scripts/run.sh --demo  # macOS app, or launch the bundle with --demo
```

What is fake in demo output:

- addresses come from the reserved documentation ranges — TEST-NET-1 `192.0.2.x`, TEST-NET-2 `198.51.100.x`, TEST-NET-3 `203.0.113.x`, and `2001:db8::/32` for IPv6
- domain lookups use `example.com`
- the ISP is literally `Example ISP (AS64500)`, the location is Amsterdam, and the hostname is `demo-mac`

Everything else — table layout, columns, ranking, apply prompts — is the real code path. Demo mode makes **no network requests** and **never changes DNS settings**, so it is safe on a locked-down machine. Resolver timings in demo output are illustrative, not measurements.

The app also has screenshot flags, which is how the images above were made:

```sh
"releases/DNS Bench.app/Contents/MacOS/DNS Bench" --demo \
  --screenshot=docs/screenshots/app-overview.png \
  --screenshot-screen=overview \
  --screenshot-delay=1800
```

- `--screenshot=<png>` writes a PNG and exits; without it the app runs normally.
- `--screenshot-screen=overview|benchmark|network|history|settings` picks the screen.
- `--screenshot-delay=<ms>` waits before capturing (default 1800).
- `--screenshot-run` starts a demo benchmark first, so the table is populated.
- `--screenshot-scroll=<px>` scrolls the content area before capturing.

The CLI screenshots are terminal captures of the demo output:

```sh
./dns-bench.zsh demo
./dns-bench.zsh speed -q --no-upload
```

## install

### macOS / Linux

```sh
curl -fsSL https://raw.githubusercontent.com/dharmsharmaa/dns-bench/main/dns-bench.zsh -o dns-bench.zsh
chmod +x dns-bench.zsh
./dns-bench.zsh
```

`chmod +x` is what makes the script executable. If you forget it you get `permission denied`. You only need to do it once per download.

No zsh yet? The script bootstraps itself:

```sh
sh dns-bench.zsh          # works from sh or bash; it re-execs under zsh
bash dns-bench.zsh        # same
```

If zsh is missing it detects your package manager (`brew`, `apt`, `dnf`, `yum`, `pacman`, `zypper`, `apk`), shows the exact command, and offers to run it. For unattended setup:

```sh
DNSBENCH_ASSUME_YES=1 sh dns-bench.zsh
```

If it is not a terminal it refuses to install silently and prints the command instead. zsh ships with macOS; this matters mainly on minimal Linux images.

Prefer a command instead of `./dns-bench.zsh`:

```sh
./dns-bench.zsh install          # ~/.local/bin/dns-bench
./dns-bench.zsh install --system # /usr/local/bin/dns-bench (sudo)
dns-bench
```

Requirements: `dig`, `curl`, `perl`, `awk`, `nc`, `ping`. All ship with macOS. On Linux install `dnsutils` / `bind-utils` plus `iproute2`. `sudo` is only used for `networksetup`/`nmcli`/`resolv.conf` changes, flushing the DNS cache, and `--system` installs, and it asks before doing anything.

### Windows

```powershell
curl.exe -fsSL https://raw.githubusercontent.com/dharmsharmaa/dns-bench/main/dns-bench.ps1 -o dns-bench.ps1
powershell -ExecutionPolicy Bypass -File .\dns-bench.ps1
```

Windows blocks downloaded scripts by default. Two options:

```powershell
# run without changing any system setting
powershell -ExecutionPolicy Bypass -File .\dns-bench.ps1

# or unblock the file once, then run it normally
Unblock-File .\dns-bench.ps1
.\dns-bench.ps1
```

Changing DNS needs an **elevated PowerShell** (Run as Administrator); benchmarking works as a normal user. Works with Windows PowerShell 5.1 and PowerShell 7+.

To use it as a command, keep the file somewhere permanent and add a wrapper to your PowerShell profile:

```powershell
New-Item -ItemType Directory -Force "$HOME\bin" | Out-Null
Move-Item .\dns-bench.ps1 "$HOME\bin\dns-bench.ps1"
Add-Content $PROFILE 'function dns-bench { & "$HOME\bin\dns-bench.ps1" @args }'
```

Open a new PowerShell window, then `dns-bench` works like it does on macOS/Linux.

> The raw URLs above point at the canonical repo. If you fork this, replace the URL in the two commands and in the `UPDATE_URL` / `$script:UpdateUrl` constants at the top of each script.

## macOS app

There is also a Mac app. Source lives in [`source/`](./source); build products, `node_modules` and the packaged app in `releases/` stay on your machine and are git-ignored, so only `source/app/` and `source/scripts/` are versioned.

```sh
source/scripts/build.sh    # builds releases/DNS Bench.app
source/scripts/run.sh      # builds if needed, then opens it
source/scripts/dev.sh      # live development (Electron)
```

The app uses the same probe logic as the CLI:

- **Overview** — glass gauge with the best score, current DNS vs the fastest switchable resolver, IPv6/ISP cards, last run, and a ranked top-5 list.
- **Benchmark** — filters (unfiltered / filtered / ads / current), search, sortable table with latency bars, live progress, auto-selected inspector with every probe result and a one-click Apply.
- **Network** — identity, connection, DNS source, and health checks (interception, captive portal, IPv6, VPN/proxy).
- **History** — last 20 runs kept on this Mac; load any of them back into the table.
- **Settings** — samples, domain, concurrency, auto-export, IPv6, results folder, About.
- **Menu bar + tray** — run, apply best, reset DNS, open results. CSV is written to `~/Library/Application Support/DNS Bench/results` after every run.

A workspace agent lives at [`.github/agents/mac-developer.agent.md`](./.github/agents/mac-developer.agent.md). It encodes the design bar (Apple HIG, Liquid Glass, typography, motion, accessibility, packaging) and the toolchain constraints for anyone — human or AI — touching the app.

Requirements: macOS 12+, Node 22 for building. The app needs the same `dig`/`curl`/`ping`/`networksetup` that ship with macOS; changing DNS triggers the normal macOS administrator prompt.

> This machine only had Command Line Tools, so there is no SwiftUI SDK to compile against. The app is an Electron shell with a native macOS window (hidden inset titlebar, real vibrancy, traffic lights, forced dark appearance, empty `default_app.asar`, ad-hoc signed bundle) and a hand-built glass interface. It looks and behaves like a Mac app, but the chassis is Electron. When Xcode is available, the same views can be ported to SwiftUI — the design contract lives in [`source/app/DESIGN.md`](./source/app/DESIGN.md).

### the app build

`releases/DNS Bench.app` is **not** in git. It is a 253 MB local build artifact produced by `source/scripts/build.sh` (Electron runtime plus the app payload and generated icons), and it is deliberately ignored. Cloning the repo does not give you a binary; you build one.

**is it safe?** Reasonable question for an unsigned `.app`:

- It is **ad-hoc signed** (`codesign --sign -`). There is no Developer ID, so it is **not notarized**. On another Mac, Gatekeeper shows the “unidentified developer” prompt.
- To open it anyway: right-click the app → **Open** → **Open**, or clear the quarantine flag:
  ```sh
  xattr -dr com.apple.quarantine "releases/DNS Bench.app"
  ```
- The bundle contains app code and the Electron runtime only — **no history, no results, no settings, no personal data**. History and CSVs live outside the bundle in `~/Library/Application Support/DNS Bench`.
- It has the same access as the CLI you would otherwise run: `dig`, `curl`, `ping`, and `networksetup` when you click Apply.

**distributing it:** don't commit the bundle. Zip it and attach the zip to a GitHub Release, or tell people to run `source/scripts/build.sh` themselves. Committing a 253 MB binary would bloat the repo permanently and would not be reproducible; the build script is.

## commands

| command | zsh | PowerShell | what it does |
|---|---|---|---|
| `run` (default) | `./dns-bench.zsh` | `.\dns-bench.ps1` | full benchmark + tables, then asks what to apply |
| `info` | `dns-bench info` | `.\dns-bench.ps1 info` | network info only |
| `test DOMAIN` | `dns-bench test example.com` | `.\dns-bench.ps1 test example.com` | troubleshoot a domain |
| `best` | `dns-bench best` | `.\dns-bench.ps1 best` | quick benchmark, apply the fastest unfiltered resolver |
| `adblock [off]` | `dns-bench adblock` | `.\dns-bench.ps1 adblock` | apply the fastest ad-blocking resolver (`off` = automatic DNS) |
| `set NAME\|#` | `dns-bench set cloudflare` | `.\dns-bench.ps1 set cloudflare` | apply a resolver without benchmarking |
| `reset` | `dns-bench reset` | `.\dns-bench.ps1 reset` | back to automatic DNS (DHCP/router) |
| `flush` | `dns-bench flush` | `.\dns-bench.ps1 flush` | clear the OS DNS cache |
| `status` | `dns-bench status` | `.\dns-bench.ps1 status` | what DNS you use now |
| `list` | `dns-bench list` | `.\dns-bench.ps1 list` | print the resolver list |
| `speed` | `dns-bench speed` | `.\dns-bench.ps1 speed` | network speed test: latency, jitter, download, upload |
| `demo` | `dns-bench demo` | `.\dns-bench.ps1 demo` | print a full sample run with fake data (no network, no changes) |
| `auto` | `dns-bench auto` | — | unattended: quick benchmark, switch only if clearly better |
| `cron WHEN\|off` | `dns-bench cron daily` | — (use Task Scheduler) | schedule `auto` |
| `install` / `uninstall` | `dns-bench install` | see above | add/remove the `dns-bench` command |
| `update` | `dns-bench update` | `.\dns-bench.ps1 update` | pull the latest script from GitHub |
| `version`, `help` | `dns-bench version` | `.\dns-bench.ps1 version` | version / help |

## clear the DNS cache

Switching resolvers is only half the job; the OS may keep handing out answers from the old one. `dns-bench flush` does the right thing per platform:

```sh
dns-bench flush          # macOS / Linux
.\dns-bench.ps1 flush    # Windows (elevated shell for the system cache)
```

What it runs:

| platform | command |
|---|---|
| macOS | `dscacheutil -flushcache; killall -HUP mDNSResponder` |
| Linux (systemd-resolved) | `resolvectl flush-caches`, or `systemd-resolve --flush-caches` on older installs |
| Linux (nscd) | `nscd -i hosts` |
| Windows | `Clear-DnsClientCache` then `ipconfig /flushdns` |

Use it after `set`, `best`, `adblock`, or `reset`, or whenever a site resolves to a stale or wrong address even though `dig @1.1.1.1` looks correct. macOS and the systemd paths need elevation, so `sudo` is used or requested. If the system has no `resolvectl`, `systemd-resolve`, or `nscd`, the cache is upstream in the router and the command tells you there is nothing local to flush.

## options

zsh flags and their PowerShell equivalents:

| zsh | PowerShell | meaning |
|---|---|---|
| `-d DOMAIN` | `-Domain` | domain for the cached test (default `google.com`) |
| `-n N` | `-Samples N` | samples per resolver, 1-20 (default 5) |
| `-t K` | `-TopK K` | resolvers in the service test, 1-12 (default 5) |
| `-x LIST` | `-ExtraServices` | extra hostnames for the service test |
| `-o FILE` | `-Csv FILE` | save results as CSV to FILE |
| `--no-csv` | `-NoCsv` | don't auto-save a CSV |
| `--no-progress` | `-NoProgress` | plain output, no progress bar |
| `-r LIST` | — | (test) extra resolver IPs |
| `-T LIST` | — | (test) record types to show |
| `-s` | `-SkipServices` | skip the popular-service test |
| `-c` | `-SkipGeo` | skip the continent test |
| `-q` | `-Quick` | quick mode (skip services + continents, 3 samples) |
| `-P` | `-Privacy` | no external IP/geo lookups |
| `-N` | `-ReportOnly` | never change DNS |
| `-y` | `-Yes` | don't ask, apply the best resolver |
| `--profile P` | — | `auto`/`cron`: `best` or `adblock` |
| `--min-gain PCT` | — | `auto`: only switch if this much better (default 20) |
| `--at HH:MM` | — | `cron`: time of day |
| `--system` | — | install into `/usr/local/bin` |
| `--duration SECS` | `-Duration SECS` | (speed) seconds per phase, 2-60 (default 10, `-q`/`-Quick` uses 4) |
| `--no-upload` | `-NoUpload` | (speed) skip the upload test |

Examples:

```sh
./dns-bench.zsh -q -N              # fast, report only
./dns-bench.zsh -n 10 -t 8         # more samples, more resolvers in the service test
./dns-bench.zsh test github.com    # why is this domain broken
./dns-bench.zsh best -y            # quick benchmark and apply the winner
./dns-bench.zsh speed              # download + upload speed test
./dns-bench.zsh speed -q           # 4 second phases
```

```powershell
.\dns-bench.ps1 -Quick -ReportOnly
.\dns-bench.ps1 -Samples 10 -TopK 8
.\dns-bench.ps1 test github.com
.\dns-bench.ps1 best -Yes
.\dns-bench.ps1 speed
.\dns-bench.ps1 speed -Duration 4 -NoUpload
```

`DNSBENCH_JOBS=N` (zsh) changes how many probes run at once (default 24).

## progress bar and csv

While probing, both versions show a progress bar. zsh updates it in place and auto-scrolls cleanly to the results; PowerShell uses the native `Write-Progress` bar. Use `--no-progress` / `-NoProgress` for plain log output.

Every `run`/`best`/`adblock` writes a timestamped CSV **next to the script**:

```
dns-bench-<hostname>-YYYYmmdd-HHMMSS.csv
```

- `-o FILE` / `-Csv FILE` writes to an explicit path instead.
- `--no-csv` / `-NoCsv` disables the automatic file.
- `DNSBENCH_CSV_DIR=/path` changes the directory (falls back to `$HOME` if the script directory is not writable, e.g. `/usr/local/bin`).

Columns: `sortkey, idx, name, kind, region, cached_ms, jitter_ms, loss_pct, cold_ms, score, v4_ping, v6_dns, v6_ping, dnssec, nxdomain, tcp53, dot853, port443, blocks_ads, pop`.

## speed test

`dns-bench speed` measures the link itself — DNS choice does not affect it.

- **Latency and jitter** to 1.1.1.1 (falls back to 8.8.8.8), via ICMP.
- **Download** and **upload** against Cloudflare's speed endpoint, using parallel streams so fast links are not bottlenecked by a single connection.
- Live meter while downloading, then a compact summary. `-o FILE` / `-Csv FILE` writes a small `metric,value,unit` CSV.

```sh
./dns-bench.zsh speed                  # 10 s per phase
./dns-bench.zsh speed --duration 5     # shorter
./dns-bench.zsh speed --no-upload      # don't burn upstream bandwidth
./dns-bench.zsh speed -q -o speed.csv  # 4 s phases + CSV
```

```powershell
.\dns-bench.ps1 speed
.\dns-bench.ps1 speed -Duration 5 -NoUpload
```

Cloudflare rate-limits bursty use (HTTP 429). When that happens the CLI retries nothing blindly, switches to the OVH mirror for download, and says so in the output — uploads need Cloudflare, so that phase reports the rate limit and is skipped. Numbers from different mirrors are not directly comparable; the output always names the mirror it used.

`-q` / `-Quick` shortens each phase to 4 seconds; `--duration` / `-Duration` accepts 2-60.

## updating

```sh
./dns-bench.zsh update --check   # is there a newer version?
./dns-bench.zsh update           # download, validate, back up, replace
./dns-bench.zsh update --force   # reinstall even if the version matches
```

```powershell
.\dns-bench.ps1 update -Check
.\dns-bench.ps1 update
.\dns-bench.ps1 update -Force
```

The source URL lives at the top of each script (`UPDATE_URL` in zsh, `$script:UpdateUrl` in PowerShell). Override it per run without editing:

```sh
DNSBENCH_UPDATE_URL=https://example.com/dns-bench.zsh ./dns-bench.zsh update
```

The zsh updater runs `zsh -n` on the download and refuses to install a file that is not a script or has a syntax error. The old version is kept as `dns-bench.zsh.<version>.bak`.

## picking a resolver

At the end of a run it asks what to do:

- enter / `best` : fastest unfiltered resolver
- `svc` : best for the popular services test
- a number : that row from the tables
- `reset` : back to automatic DNS
- `q` : quit

Filtered resolvers (malware/family/adblock) are marked `F` or `A` and never get picked automatically. Your current DNS and your router show up as `C` rows so you can compare. Your old settings are appended to `~/.dns-bench-previous.txt` before anything changes.

## notes

- takes 1-2 min with everything on. `-q` / `-Quick` is much faster.
- run it a couple of times; Wi-Fi noise moves numbers around.
- some resolver IPs were written from memory. If one shows `Timeout` every time, check the address.
- the ad-block column is a guess based on a few domains, don't trust it much.
- external lookups (cloudflare trace, ipwho.is) see your public IP. Use `-P` / `-Privacy` if you don't want that.
- `demo` mode never touches DNS, and never makes a request: no lookups, no speed test, no geo lookup.
- the zsh script can bootstrap itself (`sh dns-bench.zsh`) and installs zsh on request when it is missing.
- macOS and Linux are fully supported by the zsh script. The PowerShell version targets Windows and uses `Resolve-DnsName`, `Get-NetAdapter`, and `Set-DnsClientServerAddress`; a few macOS-only checks (traceroute hop detail, port-53 interception) are not part of the Windows version.

## credits

`dns-bench` stands on other people's infrastructure and tools: the resolver operators whose public endpoints get benchmarked, the measurement endpoints used for throughput, geo and DNSSEC checks, and the system utilities each platform ships. [`CREDITS.md`](./CREDITS.md) lists them by group, with links.

Short version: thanks to Cloudflare, Google, Quad9, AdGuard, Control D, NextDNS and the rest of the public resolver community; to `dig`, `curl`, `ping`, and the OS networking tools; to Electron and Node for making a Mac app possible without Xcode; and to GRC DNS Benchmark, DNSPerf and the public resolver test pages for showing what a useful DNS measurement looks like. Trademarks belong to their owners; being listed is not an endorsement.

## license and usage

MIT. See [LICENSE](./LICENSE).

You are free to use, copy, modify, merge, publish, distribute, sublicense, and sell copies of this software, including commercially. Keep the copyright notice, and don't blame me if your DNS breaks. Attribution is appreciated but the license does not require it beyond keeping the notice.

If this saved you some time, the only thing I ask is that you point people at [dharmsharma.com](https://dharmsharma.com).

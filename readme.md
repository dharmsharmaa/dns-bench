# dns-bench

**Your "best DNS" is someone else's.** One command that benchmarks ~50 public resolvers from the machine you are actually on, tells you the truth about your link, and can switch DNS for you.

CLI first: macOS, Linux, Windows. No daemon, no telemetry, no dependencies beyond what ships with your OS. **v3.2.0**, MIT. A Mac app exists too — [it is at the bottom](#the-mac-app).

<img src="docs/screenshots/cli-benchmark.png" alt="dns-bench CLI benchmark output" width="880">

*cached vs cold latency, jitter, loss, score — every resolver, ranked.*

## install

**macOS / Linux** — one line, no clone:

```sh
curl -fsSL https://raw.githubusercontent.com/dharmsharmaa/dns-bench/main/dns-bench.zsh -o dns-bench.zsh
chmod +x dns-bench.zsh
./dns-bench.zsh
```

`chmod +x` is what makes it executable; forget it and you get `permission denied`. Once per download.

**Windows** (PowerShell):

```powershell
curl.exe -fsSL https://raw.githubusercontent.com/dharmsharmaa/dns-bench/main/dns-bench.ps1 -o dns-bench.ps1
powershell -ExecutionPolicy Bypass -File .\dns-bench.ps1
```

Windows blocks downloaded scripts. Either use `-ExecutionPolicy Bypass` like above, or unblock once and run normally:

```powershell
Unblock-File .\dns-bench.ps1
.\dns-bench.ps1
```

Changing DNS needs an **elevated PowerShell**; benchmarking works as a normal user. Windows PowerShell 5.1 and PowerShell 7+ both work.

No zsh? The script bootstraps itself and offers to install it — `sh dns-bench.zsh` or `bash dns-bench.zsh` re-execs under zsh. It detects `brew`, `apt`, `dnf`, `yum`, `pacman`, `zypper` or `apk`, shows the command, and asks first. Unattended: `DNSBENCH_ASSUME_YES=1 sh dns-bench.zsh`.

Requirements: `dig`, `curl`, `perl`, `awk`, `nc`, `ping` — all ship with macOS. On Linux: `dnsutils`/`bind-utils` plus `iproute2`.

## install as a system command

Run it as `dns-bench` from anywhere, not `./dns-bench.zsh`:

```sh
./dns-bench.zsh install           # ~/.local/bin/dns-bench (no sudo)
./dns-bench.zsh install --system  # /usr/local/bin/dns-bench (sudo)
dns-bench
```

`install` picks `~/.local/bin` by default and tells you if that is not in your `PATH`. `--system` puts it in `/usr/local/bin` for every user. Either way it `chmod 755`s the copy, so no more `permission denied` after an update.

Windows equivalent — keep the file somewhere permanent and wrap it in your profile:

```powershell
New-Item -ItemType Directory -Force "$HOME\bin" | Out-Null
Move-Item .\dns-bench.ps1 "$HOME\bin\dns-bench.ps1"
Add-Content $PROFILE 'function dns-bench { & "$HOME\bin\dns-bench.ps1" @args }'
```

Open a new PowerShell window and `dns-bench` works the same way.

Once installed, `dns-bench update` replaces the command in place (and any copy in `PATH`) after checking the download is a valid script. `dns-bench uninstall` removes the command and any schedule.

## speed test

No need to open speedtest.net, fast.com or a dozen tabs. `dns-bench speed` measures the link itself — DNS choice does not affect it.

```sh
dns-bench speed                     # latency, jitter, download, upload
dns-bench speed --duration 5        # shorter phases
dns-bench speed --no-upload         # don't burn upstream bandwidth
dns-bench speed -q -o speed.csv     # 4 s phases + CSV
```

```powershell
.\dns-bench.ps1 speed
.\dns-bench.ps1 speed -Duration 5 -NoUpload
```

- **Latency and jitter** to 1.1.1.1 (falls back to 8.8.8.8) over ICMP.
- **Download and upload** against Cloudflare's speed endpoint using parallel streams, so a fast link is not bottlenecked by one connection. Live meter while it runs.
- Reports the download/upload ratio, so you can see whether your "fibre" is actually symmetric.

Cloudflare rate-limits bursty use (HTTP 429). When that happens the CLI does not retry blindly: it retries once, falls back to the OVH mirror for download, and names the mirror it used. Uploads need Cloudflare, so that phase reports the limit and is skipped rather than faking a number.

<img src="docs/screenshots/cli-speed.png" alt="dns-bench speed test output" width="820">

*cli — latency, jitter, download, upload. No browser needed.*

This is the fastest way to answer "is the site slow because of DNS or because my connection is bad?" — run `speed` and `test DOMAIN` side by side.

## popular services test

Because fastest lookup is not the same as closest edge. The script resolves ~30 real services through the top resolvers, then times an actual TCP connect to the IP each resolver handed back:

google, youtube, google meet, facebook, instagram, whatsapp web, x, linkedin, reddit, netflix, prime video, spotify, hotstar, apple, microsoft, teams, zoom, amazon, flipkart, github, npm, pypi, docker hub, openai, anthropic, cdnjs, jsdelivr, aws s3, steam, wikipedia.

If one resolver sends you to a nearby CDN edge and another sends you across an ocean, this is the table that shows it. Add your own hosts with `-x`:

```sh
dns-bench -x "internal.example.com,shop.example.com"
dns-bench -t 8        # test the top 8 resolvers instead of 5
dns-bench -s          # skip this test entirely (faster run)
```

## schedule it (cron)

DNS changes as your ISP re-routes, so set it and forget it. `auto` re-benchmarks and **only switches if the new resolver is clearly better** (default: 20% better score), so it will not flap on noise.

```sh
dns-bench install                                  # needed once, for cron
dns-bench cron hourly
dns-bench cron 6h
dns-bench cron daily --at 04:00
dns-bench cron weekly --at 03:30
dns-bench cron 2d                                  # every N days (1-30)
dns-bench cron 7d --at 02:00
dns-bench cron "0 4 */2 * *"                       # raw 5-field cron (Linux)
dns-bench cron off                                 # remove the schedule
```

- macOS: a **launchd** daemon (`com.dns-bench.auto`), runs as root, logs to `/var/log/dns-bench.log`. `hourly`, `6h`, `daily`, `weekly` and `Nd` are supported; for `Nd` macOS uses a fixed interval, so the time of day comes from when you scheduled it rather than `--at`.
- Linux: `/etc/cron.d/dns-bench`, root crontab, or a systemd timer as a fallback. Raw cron expressions are accepted, so any interval you can express works.
- `--profile adblock` schedules the ad-blocking profile instead of the fastest resolver:

```sh
dns-bench cron daily --at 04:00 --profile adblock
dns-bench cron daily --at 04:00 --min-gain 30   # switch only if 30% better
```

Check what is scheduled, what DNS you use, and where the log is:

```sh
dns-bench status
```

## quick start

```sh
dns-bench                 # full run, then asks what to apply
dns-bench -q -N           # ~40 seconds, report only, changes nothing
dns-bench best -y         # quick benchmark, apply the winner
dns-bench test example.com  # why is this one domain broken
dns-bench speed           # is the link slow, or is it DNS?
dns-bench flush           # clear the OS cache after switching
```

```powershell
.\dns-bench.ps1
.\dns-bench.ps1 -Quick -ReportOnly
.\dns-bench.ps1 best -Yes
.\dns-bench.ps1 speed
```

`-N` / `-ReportOnly` is the safe one: it prints everything and touches nothing. Run that first on any machine before letting it change your DNS.

## the part that surprised me

Rank by cached latency and Google wins. Rank by what you actually feel — first lookups, not a warm cache — and it loses badly. From one run on my network (52 resolvers, 3 samples, Wi-Fi):

```
resolver             cached    cold
Google                 44      162
Cloudflare             53      141
Quad9 (unfiltered)     49      141
Neustar UltraDNS       59       58   <- won
my router               9       95
```

Neustar won *despite* the worst cached latency of that group, because it had the best worst case. My router beat every public resolver on cached lookups by 4-5x and fell apart the moment anything was cold.

That inversion is the whole point. One number would have picked Google. It is also why the score weights cold lookups double:

```
(cached + 2*cold) / 3 + 3*loss%
```

## commands

| command | zsh | PowerShell | what it does |
|---|---|---|---|
| `run` (default) | `dns-bench` | `.\dns-bench.ps1` | full benchmark + tables, then asks what to apply |
| `info` | `dns-bench info` | `.\dns-bench.ps1 info` | network info only |
| `test DOMAIN` | `dns-bench test example.com` | `.\dns-bench.ps1 test example.com` | troubleshoot a domain |
| `best` | `dns-bench best` | `.\dns-bench.ps1 best` | quick benchmark, apply the fastest unfiltered resolver |
| `adblock [off]` | `dns-bench adblock` | `.\dns-bench.ps1 adblock` | apply the fastest ad-blocking resolver (`off` = automatic DNS) |
| `set NAME\|#` | `dns-bench set cloudflare` | `.\dns-bench.ps1 set cloudflare` | apply a resolver without benchmarking |
| `reset` | `dns-bench reset` | `.\dns-bench.ps1 reset` | back to automatic DNS (DHCP/router) |
| `flush` | `dns-bench flush` | `.\dns-bench.ps1 flush` | clear the OS DNS cache |
| `status` | `dns-bench status` | `.\dns-bench.ps1 status` | DNS in use, installed copy, schedule, last log |
| `list` | `dns-bench list` | `.\dns-bench.ps1 list` | print the resolver list |
| `speed` | `dns-bench speed` | `.\dns-bench.ps1 speed` | speed test: latency, jitter, download, upload |
| `auto` | `dns-bench auto` | — | unattended: quick benchmark, switch only if clearly better |
| `cron WHEN\|off` | `dns-bench cron 2d` | — (Task Scheduler) | schedule `auto` |
| `install` / `uninstall` | `dns-bench install` | see above | add/remove the `dns-bench` command |
| `demo` | `dns-bench demo` | `.\dns-bench.ps1 demo` | print a full sample run (no network, no changes) |
| `update` | `dns-bench update` | `.\dns-bench.ps1 update` | pull the latest script from GitHub |
| `version`, `help` | `dns-bench version` | `.\dns-bench.ps1 version` | version / help |

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

`DNSBENCH_JOBS=N` changes how many probes run at once (default 24). `DNSBENCH_CSV_DIR=/path` changes where CSVs go.

## what it measures

**Per resolver** — median cached latency, median cold latency (random names under com/net/org so nothing is warm), jitter, packet loss, DNSSEC validation, NXDOMAIN hijacking, TCP/53, DoT:853, 443 reachability, a rough ad-block check, and which anycast PoP answered.

**Your network** — local IPs, gateway and latency, public IPv4/IPv6, ISP/ASN, location, VPN/proxy, DNS in use, nearest Cloudflare PoP, first traceroute hops. Also checks whether your router or ISP is intercepting port 53, and whether you are behind a captive portal.

**Distance, not opinion** — TCP connect time to AWS regions on every continent. Physical distance, independent of which DNS you pick.

**Popular services** — see [above](#popular-services-test).

**Speed** — see [above](#speed-test).

**Troubleshooting** — `test DOMAIN` compares resolvers, prints records, checks authoritative name servers and SOA serials, DNSSEC, TCP/HTTPS reachability, and ends with a plain-English verdict.

## why i made this

Most "best DNS" lists are written from a datacenter somewhere else. The resolver that wins on a blog post is often not the one that is fastest from your couch, on your ISP, on your Wi-Fi. I wanted one command that answers the boring but useful questions:

- which resolver is actually fastest from *this* network right now?
- is my router or ISP hijacking DNS or rewriting NXDOMAIN?
- does the resolver validate DNSSEC, block ads, answer over TCP/DoT, and which anycast node do I land on?
- which resolver hands me the closest CDN edge for the sites I actually use?
- why does one domain fail while everything else works?

So it measures instead of guessing, shows you the numbers, and then optionally applies the winner — with a backup of your old settings in `~/.dns-bench-previous.txt`.

## picking a resolver

At the end of a run it asks what to do:

- enter / `best` : fastest unfiltered resolver
- `svc` : best for the popular services test
- a number : that row from the tables
- `reset` : back to automatic DNS
- `q` : quit

Filtered resolvers (malware/family/adblock) are marked `F` or `A` and never get picked automatically. Your current DNS and your router show up as `C` rows so you can compare. `sudo` is only used for `networksetup`/`nmcli`/`resolv.conf` changes, flushing the cache, and `--system` installs, and it asks before doing anything.

## clear the DNS cache

Switching resolvers is only half the job; the OS may keep handing out answers from the old one.

```sh
dns-bench flush          # macOS / Linux
.\dns-bench.ps1 flush    # Windows
```

| platform | command |
|---|---|
| macOS | `dscacheutil -flushcache; killall -HUP mDNSResponder` |
| Linux (systemd-resolved) | `resolvectl flush-caches`, or `systemd-resolve --flush-caches` on older installs |
| Linux (nscd) | `nscd -i hosts` |
| Windows | `Clear-DnsClientCache` then `ipconfig /flushdns` |

Use it after `set`, `best`, `adblock` or `reset`, or whenever a site resolves to a stale address while `dig @1.1.1.1` looks correct. If there is no `resolvectl`, `systemd-resolve` or `nscd`, the cache is upstream in your router and the command says so.

## progress bar and csv

Both versions show a progress bar. zsh updates it in place and scrolls cleanly into the results; PowerShell uses the native `Write-Progress` bar. Use `--no-progress` / `-NoProgress` for plain log output, which is what you want in cron logs.

Every `run`/`best`/`adblock` writes a timestamped CSV **next to the script**:

```
dns-bench-<hostname>-YYYYmmdd-HHMMSS.csv
```

- `-o FILE` / `-Csv FILE` writes to an explicit path instead.
- `--no-csv` / `-NoCsv` disables the automatic file.
- `DNSBENCH_CSV_DIR=/path` changes the directory (falls back to `$HOME` if the script directory is not writable, e.g. `/usr/local/bin`).

Columns: `sortkey, idx, name, kind, region, cached_ms, jitter_ms, loss_pct, cold_ms, score, v4_ping, v6_dns, v6_ping, dnssec, nxdomain, tcp53, dot853, port443, blocks_ads, pop`.

## demo mode

Do not want to expose your network in a screenshot, and do not want to trust a stranger's? `demo` prints a full-looking run from hardcoded data.

```sh
dns-bench demo             # macOS / Linux
.\dns-bench.ps1 demo       # Windows
```

Fake, and obviously so: TEST-NET addresses (`192.0.2.x`, `198.51.100.x`, `203.0.113.x`), `2001:db8::/32`, `example.com`, `Example ISP (AS64500)`, hostname `demo-mac`, Amsterdam. Layout, columns, ranking and prompts are the real code path. It makes **no network requests** and **never changes DNS**. Every screenshot in this README comes from it.

<img src="docs/screenshots/cli-demo.png" alt="dns-bench demo output, full run" width="820">

*cli — a full `demo` run: network block, benchmark, features, regions, speed, summary.*

## updating

```sh
dns-bench update --check   # is there a newer version?
dns-bench update           # download, validate, back up, replace
dns-bench update --force   # reinstall even if the version matches
```

```powershell
.\dns-bench.ps1 update -Check
.\dns-bench.ps1 update -Force
```

The source URL lives at the top of each script (`UPDATE_URL` in zsh, `$script:UpdateUrl` in PowerShell). Override per run: `DNSBENCH_UPDATE_URL=https://example.com/dns-bench.zsh dns-bench update`. The zsh updater runs `zsh -n` on the download, refuses anything that is not a script or has a syntax error, and keeps the old version as `dns-bench.zsh.<version>.bak`.

## notes

- takes 1-2 min with everything on; `-q` / `-Quick` is much faster.
- run it a couple of times; Wi-Fi noise moves numbers around.
- some resolver IPs were written from memory. If one shows `Timeout` every time, check the address.
- the ad-block column is a guess based on a few domains, don't trust it much.
- external lookups (cloudflare trace, ipwho.is) see your public IP. Use `-P` / `-Privacy` if you don't want that.
- `demo` mode never touches DNS, and never makes a request.
- the zsh script can bootstrap itself and installs zsh on request when it is missing.
- macOS and Linux are fully supported by the zsh script. The PowerShell version targets Windows and uses `Resolve-DnsName`, `Get-NetAdapter`, `Set-DnsClientServerAddress`; a few macOS-only checks (traceroute hop detail, port-53 interception) are not in the Windows version.

## the mac app

Optional. Same probe engine, wrapped in a window — the CLI is the project, this is a convenience.

| | |
|---|---|
| <img src="docs/screenshots/app-overview.png" alt="app overview"> | <img src="docs/screenshots/app-benchmark.png" alt="app benchmark table"> |
| *overview — score gauge, current DNS, top 5* | *benchmark — sortable table with Apply* |
| <img src="docs/screenshots/app-network.png" alt="app network screen"> | <img src="docs/screenshots/app-settings.png" alt="app settings screen"> |
| *network — identity, DNS source, health checks* | *settings — samples, domain, concurrency* |

```sh
source/scripts/build.sh    # builds releases/DNS Bench.app
source/scripts/run.sh      # builds if needed, then opens it
source/scripts/dev.sh      # live development (Electron)
```

Screens: overview, benchmark (filters, search, inspector, Apply), network, history (last 20 runs), settings. Menu bar item for run / apply best / reset DNS / open results. CSV lands in `~/Library/Application Support/DNS Bench/results`.

Source is in [`source/`](./source); build products, `node_modules` and the packaged app in `releases/` stay on your machine and are git-ignored. Only `source/app/` and `source/scripts/` are versioned. Design contract: [`source/app/DESIGN.md`](./source/app/DESIGN.md).

Requirements: macOS 12+, Node 22 for building.

> There was no Xcode on the build machine, so no SwiftUI SDK to compile against. It is an Electron shell with a native macOS window (hidden inset titlebar, real vibrancy, traffic lights, forced dark appearance, ad-hoc signed bundle) and a hand-built glass interface. Portable to SwiftUI when Xcode is available.

### is the app build safe?

`releases/DNS Bench.app` is **not** in git — it is a 253 MB local artifact from `source/scripts/build.sh`. Cloning does not give you a binary.

- **Ad-hoc signed** (`codesign --sign -`), no Developer ID, **not notarized**. On another Mac Gatekeeper shows the "unidentified developer" prompt: right-click → **Open**, or `xattr -dr com.apple.quarantine "releases/DNS Bench.app"`.
- Contains app code and the Electron runtime only — **no history, no results, no settings, no personal data**. Those live in `~/Library/Application Support/DNS Bench`.
- Same access as the CLI: `dig`, `curl`, `ping`, and `networksetup` when you click Apply.

**Distributing it:** don't commit the bundle. Zip it and attach to a GitHub Release, or tell people to run `source/scripts/build.sh`.

A workspace agent lives at [`.github/agents/mac-developer.agent.md`](./.github/agents/mac-developer.agent.md), encoding the design bar for anyone touching the app.

## credits

`dns-bench` stands on other people's infrastructure and tools: the resolver operators whose public endpoints get benchmarked, the measurement endpoints used for throughput, geo and DNSSEC checks, and the system utilities each platform ships. [`CREDITS.md`](./CREDITS.md) lists them by group, with links.

Short version: thanks to Cloudflare, Google, Quad9, AdGuard, Control D, NextDNS and the rest of the public resolver community; to `dig`, `curl`, `ping`, and the OS networking tools; to Electron and Node for the Mac app; and to GRC DNS Benchmark, DNSPerf and the public resolver test pages for showing what a useful DNS measurement looks like. Trademarks belong to their owners; being listed is not an endorsement.

## license and usage

MIT. See [LICENSE](./LICENSE).

You are free to use, copy, modify, merge, publish, distribute, sublicense, and sell copies of this software, including commercially. Keep the copyright notice, and don't blame me if your DNS breaks. Attribution is appreciated but the license does not require it beyond keeping the notice.

If this saved you some time, the only thing I ask is that you point people at [dharmsharma.com](https://dharmsharma.com).

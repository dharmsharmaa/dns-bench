# changelog

Newest first. A version number lives in two places and they always match: `VERSION=` in
`dns-bench.zsh` and `$script:Version` in `dns-bench.ps1`. A release bumps both, because a version
where the two CLIs disagree is not a release.

There are no git tags yet, so the dates below are when the version was written, not when a tag was
cut. The Mac app is versioned separately because it is frozen.

Format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Entries describe
behaviour changes, not commits — if you want the diff, read the diff.

---

## 3.4.0 — 2026-11-26

One number for the whole connection, and a trophy when it is a good one.

### Added

- **`score`.** Five lines measured and graded 0-100, then weighted into a single total: dns 35%
  (cached 50%, cold 30%, jitter 10%, loss 10%), latency 20% (ICMP 70%, jitter 20%, loss 10%), speed
  20% (download 65%, upload 35%), privacy 15% (NXDOMAIN honour 30%, DNSSEC 25%, egress match 25%,
  DoT 20%) and stability 10% (DNS loss and ICMP loss, half each). S at 93, A at 85, B at 72, C at
  58, D at 42, E below.
- **A trophy, animated, only when it is earned and only on a terminal.** Grade B and above draws an
  ASCII trophy line by line with the letter engraved and the total bar counting up to it. Grades C
  and below get the two weakest lines and the command that investigates each one instead, because a
  medal is not the useful part of a low score.
- **Drop-and-reweight.** A line that cannot be measured (no upload, ICMP blocked, speed test refused)
  is removed and the remaining weights renormalised. A closed port is not evidence of a bad
  connection, and the previous behaviour of scoring it zero would have said it was.
- **A VPN line rather than a VPN penalty.** A detected tunnel is named, and DNS is then measured
  through it. The privacy score falls on a mismatch, such as queries leaving outside the tunnel, not
  on the tunnel existing.
- `score` in `demo` mode, so the report and the trophy can be screenshotted without a network.
- **PowerShell parity.** `score` on Windows uses the same bands, weights, thresholds, layout, trophy
  and notes, and produces byte-identical output to the zsh version for the same measurements. The
  only differences are platform syntax in the advice text (`.\dns-bench.ps1 run` rather than
  `dns-bench run`) and the egress host, which reuses the helper the file already had.
- Six README feature rows (81-86) and a `### score` section in the command reference.

### Fixed

- **`./dns-bench.zsh` failed on a machine without zsh**, with only
  `bash: ./dns-bench.zsh: cannot execute: required file not found`. The shebang named `/bin/zsh`, so
  the kernel refused to exec the file and the zsh-install bootstrap never ran — it was only reachable
  via `sh dns-bench.zsh` or `bash dns-bench.zsh`. The shebang is now `/bin/sh`, which always exists,
  so the bootstrap runs and either finds zsh or offers to install it. The interpreter lookup also
  checks `/usr/bin/zsh`, `/usr/local/bin/zsh`, `/bin/zsh`, `/opt/homebrew/bin/zsh` and `/snap/bin/zsh`
  before concluding zsh is missing, because `cron`, `sudo -i` and minimal containers routinely have it
  installed but off `PATH`.

### Changed

- Command count 33 to 34. `score` sits in the `diagnose` help group.
- Version 3.4.0 in both CLIs.

### Not changed

- The benchmark's own scoring formula `(cached + 2*cold) / 3 + 3*loss%`. `score` is a separate
  rubric for the connection as a whole and does not feed the resolver ranking.
- Resolver kinds, the CSV schema, and `run`'s output.
- The Mac app, still frozen at 1.0.0.

### Notably not done

- **No percentile.** The obvious version of this feature tells you "you are in the top 12%". That
  would require a survey of other people's connections, which this project does not have and cannot
  honestly fake. The bands are a rubric drawn from what a healthy cable or fibre link does, and the
  output says so on every run.

---

## 3.3.0 — 2026-11-26

The release where it stopped being only a DNS benchmark. Also the release where a reader found a
methodology bug, which matters more than anything added here.

### Fixed

- **Cold-cache measurement was invalid.** Forked probe workers inherited the parent's `$RANDOM`, so
  every resolver in a run was asked the *same* three cold names. The first probe paid the full
  lookup; every later probe got a cache hit on a name another worker had just queried, and reported
  it as cold latency. Each probe now reseeds from high-resolution time, pid and resolver index
  before drawing anything, and every name carries a per-run salt:
  `cold-<salt>-r<resolver>-<sample>.<tld>`. No two probes within a run, and no two runs, share a
  name. The NXDOMAIN-hijack probe follows the same rule. `DNSBENCH_DEBUG_COLD=1` prints every
  generated name so the uniqueness is checkable from outside.
- Verisign and Neustar both front the same UltraDNS backend, which made the bug above worse rather
  than being a separate one: with every probe asking the same name, a query sent to Verisign warmed
  an entry that the Neustar probe then read back as a cache hit. Unique per-probe names close this,
  because a sibling's query now warms a name nobody else will ever ask for.
- `propagation` printed `resolver7` where it meant `7 resolvers`.
- `asn` and `ports` label mismatches between the zsh and PowerShell output.

### Added

- **13 network commands.** `ports http tls trace asn ptr leak propagation mtu ecs ifaces listen
  wifi`, all read-only. `asn` uses Team Cymru's DNS interface instead of whois. `tls` warns under 21
  days to expiry. `mtu` bisects with don't-fragment pings from 1500. `leak` compares resolver egress
  against your public IP. `ecs` compares `+subnet=0` against your real `/24`. Command count went from
  19 to 33, including `doctor` below.
- **A 53rd resolver**, which is the whole reason for the number: 51 static entries plus
  `Router / Gateway` and `Current system DNS` at runtime. The new static entry is `dnsforge.de`,
  an ad-blocking resolver, checked for blocking behaviour, DNSSEC validation and NXDOMAIN
  hijacking before being added rather than copied from a vendor page.
- **`doctor`**: prints the environment, every required and optional tool with a pass or missing
  mark, whether an installed copy exists, what schedule is registered, whether the log is readable,
  and the DNS currently in use. Exits 1 if a required tool is missing, so it can gate a script or a
  CI step. It is the one command allowed to fail loudly.
- PowerShell reached parity with zsh: the five resolvers it was missing (Quad9 ECS, CleanBrowsing
  Adult Filter, Yandex Family, CNNIC SDNS, LG U+) and its own implementation of all fourteen new
  commands.
- ANSI colour in zsh output, suppressed when the output is not a terminal or `NO_COLOR` is set.
- `CHANGELOG.md` (this file), `CODE_OF_CONDUCT.md`, `CONTRIBUTING.md`, `SECURITY.md`, `SUPPORT.md`,
  `.editorconfig`, a pull request template, bug and feature issue forms, a labeler config and a
  scoped Dependabot config.

### Changed

- **README is CLI-first.** Install and the command reference come before anything else; the Mac app
  moved to the bottom of the file, where it now sits as a footnote on a frozen component rather than
  as the headline. Every command has its own section with its flags, plus a table of what is
  different from browser-based DNS tests.
- `help` is grouped by task (benchmark, dns control, diagnose, network, maintenance) and
  `help <command>` prints usage and examples for a single command. In 3.2.0 the known commands were
  19 and `help` printed one flat list for all of them; `help ports` just reprinted that list.
- Feature list in the README expanded to 80 entries, each one describing implemented behaviour.

### Not changed

- The scoring formula. `(cached + 2*cold) / 3 + 3*loss%` still weights cold lookups double.
- The resolver kind letters (`U` unfiltered, `F` family, `A` ad-blocking, `C` custom) and the CSV
  schema. If a fix had required either, it would be a major version.
- The Mac app. Still 1.0.0, still Electron, still not updated with any of the above.

---

## 3.2.0 — 2026-11-21

Last version before the cold-cache fix. 50 static resolvers, 19 commands, a single script per
platform.

- Progress bar with per-resolver ticks, skipped automatically when stdout is not a terminal.
- CSV written next to the script by default (`--no-csv` to disable), progress bar and table
  auto-scrolling as resolvers finish.
- `speed`: parallel download and upload streams with a live meter, latency, jitter and loss.
- `cron` scheduling for launchd and systemd, with `--at` for time of day, `hourly` / `6h` / `daily` /
  `weekly`, and `Nd` intervals from `1d` to `30d`. On macOS, `Nd` maps to a launchd `StartInterval`
  so the time of day comes from when the job was scheduled rather than `--at`.
- `demo` mode: prints a plausible full run using documentation address ranges and
  `example.com`, makes no network requests, so it can be screenshotted safely.
- `flush`: clears the OS resolver cache — `dscacheutil` plus a `mDNSResponder` HUP on macOS,
  `resolvectl` / `systemd-resolve` / `nscd` on Linux — and says so plainly when the machine has no
  local cache to clear, instead of pretending it did something.
- `update`: pulls the latest script from GitHub, with `--check` and `--force`.
- `version` command and `--version` flag.
- `--profile best|adblock` and `--min-gain` for unattended switching.
- PowerShell version at feature parity except for five resolvers and the network commands later
  added in 3.3.0.
- macOS app reached 1.0.0 and shipped its first build.

## 3.1.0 and earlier

Not itemised — this changelog started at 3.2.0, and reconstructing earlier entries from memory would
be inventing history. What those versions were: progressively more resolvers, cached and cold
latency measurement, the composite score, the popular-services test, DNSSEC and NXDOMAIN-hijack
checks, and the `set` / `reset` / `status` / `list` commands for applying a result.

If you need the exact state of an earlier version, the commits are in the repository.

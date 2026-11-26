# security policy

`dns-bench` runs on your machine, often with `sudo`, and talks to resolvers you do not control. That
is the whole job. This page is about where the trust boundary actually sits.

## supported versions

| version | supported |
| --- | --- |
| 3.3.x | yes — fixes land here |
| 3.2.x and older | no — the frozen Mac app v1.0.0 is not patched |

The CLI is a single script, so "supported version" means the current `main` and the latest release.
There are no backports to older branches. If you are on 3.2.x, update:
`dns-bench update` on macOS/Linux.

## reporting a vulnerability

**Privately, please.** Two channels, either is fine:

- GitHub Security Advisories:
  <https://github.com/dharmsharmaa/dns-bench/security/advisories/new>


Do not open a public issue for an unreported vulnerability, and do not paste a working exploit into a
PR description. Expect an acknowledgement within a few days; this is a personal project, not a
staffed security team, so a fix may take a couple of weeks. You will be credited in the advisory
unless you would rather not be.

## in scope

- **The scripts themselves** — `dns-bench.zsh` and `dns-bench.ps1`: command injection, argument
  parsing that lets input escape into a shell, unsafe temporary files, privilege mishandling.
- **The resolver list being wrong or malicious.** An entry that points somewhere other than the
  operator's published address, or a "public" resolver that is actually collecting queries for
  someone else.
- **A command that mutates when it claims to be read-only.** Anything that changes DNS, flushes a
  cache, writes a file or installs a schedule without saying so first, or that ignores `-N`.
- **Injection through hostnames, SSIDs or interface names.** A Wi-Fi network named
  `; rm -rf ~` must be data, never code.
- **A supply-chain issue in the app build** — `source/app`, `source/scripts`, or the packaging step
  producing something other than what the source says it produces.

## out of scope

- **A public resolver operator behaving badly** — logging you, hijacking NXDOMAIN, filtering
  something you wanted, selling data. That is between you and them. Report it to the operator; the
  most this project can do is drop them from the list.
- **Your own ISP, router, or network.** DNS interception, a captive portal rewriting answers, CPE
  firmware bugs: not ours.
- **The frozen Mac app's notarisation status.** It is ad-hoc signed and not notarized, on purpose,
  and it says so in the [README](./readme.md#the-mac-app). Gatekeeper warnings on a local build are
  expected, not a vulnerability.
- **Numbers you disagree with.** A resolver scoring higher than you think it should is a benchmark
  question, not a security report.

## the trust boundary

Be clear-eyed about this before you run it:

- Benchmarking and read-only commands run as your normal user.
- **Mutating commands use `sudo`** where the platform requires it: `networksetup`/`nmcli`/`resolv.conf`
  changes, cache flushes, installing to `/usr/local/bin`, adding or removing a schedule.
- It asks before it changes anything, and **prints exactly what it is about to run**. Read that line.
  If the printed command is not the command you expected, that is the bug to report — before you
  press `y`.
- Every applied resolver is appended to `~/.dns-bench-previous.txt`, so a change is traceable.
- External lookups (`1.1.1.1/cdn-cgi/trace`, `ipwho.is`, and the speed-test endpoints) see your
  public IP. `-P` skips them. Nothing is sent to the author; there is no telemetry.

The script is plain text. Read it. That is the only audit that matters.

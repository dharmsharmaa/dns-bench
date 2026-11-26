# contributing

Thanks for wanting to help. `dns-bench` is a shell script with opinions: it measures DNS from the
machine you are on, changes nothing unless you say so, and has no dependencies past the tools your OS
already ships. Contributions that respect those three things are welcome.

Maintained by [Dharm Sharma](https://dharmsharma.com). MIT — see [LICENSE](./LICENSE).

## what is wanted

- **New resolver endpoints.** Add the address, and show that it answers: paste the `dig` output from
  a real machine. A resolver that only exists in a vendor's marketing page is not a resolver.
- **Bug reports** with `dns-bench doctor` output and the exact command you ran. The ones that take an
  hour to reproduce without that are the ones that never get fixed.
- **Docs fixes.** If the README says something the code does not do, that is a bug. Fix it.
- **Portability fixes.** Linux distro differences, macOS releases, `dig` build quirks, PowerShell 5.1
  versus 7. This is where most real-world breakage lives.
- **Corrections to [`CREDITS.md`](./CREDITS.md).** Wrong endpoint, wrong attribution, dead resolver:
  tell us.

What is **not** wanted: pull requests against the Mac app in `source/app`. It is frozen at v1.0.0 and
stays that way. The CLI is the project now. Issues that describe what you want from a GUI are fine
and get read, but no app PRs will be merged.

## run it locally

You do not need to clone to try it, but you do need to clone to change it.

```sh
curl -fsSL https://raw.githubusercontent.com/dharmsharmaa/dns-bench/main/dns-bench.zsh -o dns-bench.zsh
chmod +x dns-bench.zsh
```

No zsh on this machine? The script bootstraps itself:

```sh
sh dns-bench.zsh
```

That re-execs under zsh (installing it on request if it is missing). From a clone, the same works:
`sh ./dns-bench.zsh`. On Windows, `powershell -ExecutionPolicy Bypass -File .\dns-bench.ps1`.

## verification checklist before opening a PR

Copy-paste this. If a line fails, the PR is not ready.

```sh
zsh -n dns-bench.zsh
./dns-bench.zsh doctor
./dns-bench.zsh -q -N --no-csv --no-progress
./dns-bench.zsh help && ./dns-bench.zsh help ports
DNSBENCH_DEBUG_COLD=1 ./dns-bench.zsh -n 1 -q -N --no-csv 2>&1 | grep -c cold-
```

The last line must print a count greater than zero, and every name printed in a single run must be
distinct. Cold names are the part of the benchmark that is easy to get silently wrong.

A broken PowerShell script does not fail until it runs. Parse the AST before you ask anyone to
review:

```powershell
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
  (Resolve-Path .\dns-bench.ps1), [ref]$null, [ref]$errors)
if ($errors) { $errors; exit 1 } else { 'AST OK' }
```

There is no test framework here, and that is deliberate. The checks above are the test suite: they
parse, they run, they exercise the code paths that break.

## parity rule

**Anything added to `dns-bench.zsh` must land in `dns-bench.ps1` in the same pull request**: the same
command name, the same flags, the same output labels. A zsh-only feature is a Windows regression with
extra steps.

If a platform genuinely cannot support it — a macOS-only `scutil` path, an `nmcli`-only check — then
both scripts must print the same explanatory message, in the same words, and say why. Not a silent
omission, and not a different sentence on each platform.

## hard rules

These are the ones that actually matter. Everything else is style.

1. **No new runtime dependencies.** `dig`, `curl`, `ping`, `awk`, `perl`, `openssl` and the OS's own
   networking tools. Nothing to install, nothing to pin, nothing to CVE. If it needs a package, it
   does not belong here.
2. **Every external command has a timeout.** `curl -m`, `dig +time=`, `ping -t`/`-W`, `-w`. A hung
   probe must never hang the tool.
3. **Read-only commands never mutate state.** No DNS change, no cache flush, no file write, no
   schedule. If a command touches anything, it says so before it does it, and `-N` turns it off.
4. **Never reintroduce shared cold-query names.** A name reused across probes turns a cached hit into
   a "cold" measurement and flatters a resolver. Every cold name carries a per-run salt, the resolver
   index and the sample index; keep it that way.
5. **Quote everything.** Paths, SSIDs, interface names, hostnames, resolver addresses. No unquoted
   expansion, no `eval` of anything a user typed.

## style

Match the code that is already there. It is shell, not a framework:

- no dependencies pretending to be one — no wrapper libraries, no sourced modules, no build step;
- reuse the existing helpers (`print`, the colour variables, `timeout_cmd`, the probe functions)
  rather than writing a second version of them;
- quote everything, including things you are sure cannot contain a space;
- comments only where the reason is non-obvious. "Increment the counter" does not need a comment;
  "Verisign and Neustar share an UltraDNS backend" does.

## commits

Short imperative subject, one change per commit:

```
fix asn lookup on freebsd dig output
add dns0.eu family resolver
```

Details go in the body if they help. This repository **squashes on merge**, so the pull request
title becomes the commit that lands — write it like one.

## versions and the changelog

`CHANGELOG.md` is the record of what changed and why, and it is the only place that should be
written in the past tense about features that already work. When you change behaviour:

1. Add or extend the entry under an unreleased or new version heading. Say what the old behaviour
   was if it was wrong — a changelog that only lists additions is a release note, not a record.
2. Bump `VERSION=` in `dns-bench.zsh` and `$script:Version` in `dns-bench.ps1` together. A version
   where the two disagree is not a release.
3. Keep the README's `## changelog` summary in step with the newest entries. It is a summary, so it
   gets shorter treatment, not different facts.

Do not retitle or reorder old entries once they are written. If an entry turns out to be wrong, add a
correction to it rather than quietly rewriting history — the mistakes are part of the record, and one
of them is the reason this project is worth using.

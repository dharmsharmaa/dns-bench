## what this changes

<!-- one or two sentences. what behaviour is different after this PR? -->

## how i verified

<!-- paste the commands you ran and what you saw. screenshots of `dns-bench demo` are fine;
     redact IPs, DNS servers and gateway from real `-N` output. -->

```sh
zsh -n dns-bench.zsh
./dns-bench.zsh doctor
./dns-bench.zsh -q -N --no-csv --no-progress
./dns-bench.zsh help && ./dns-bench.zsh help ports
DNSBENCH_DEBUG_COLD=1 ./dns-bench.zsh -n 1 -q -N --no-csv 2>&1 | grep -c cold-
```

```powershell
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
  (Resolve-Path .\dns-bench.ps1), [ref]$null, [ref]$errors)
if ($errors) { $errors; exit 1 } else { 'AST OK' }
```

## checklist

- [ ] `zsh -n dns-bench.zsh` passes, and the PowerShell AST parse is clean
- [ ] `./dns-bench.zsh doctor` is green on this machine
- [ ] `./dns-bench.zsh -q -N --no-csv --no-progress` runs to completion
- [ ] `DNSBENCH_DEBUG_COLD=1 ... grep -c cold-` prints a non-zero count, all names in the run distinct
- [ ] **parity**: the same command name, flags and output labels exist in `dns-bench.ps1`, or both
      scripts print the same explanatory message explaining why the platform cannot support it
- [ ] **docs**: `readme.md` (and `CREDITS.md` for resolver or endpoint changes) updated in this PR
- [ ] **labelled honestly**: every command this touches is correctly described as read-only or
      mutating, and `-N` still prevents the mutation
- [ ] **no new dependencies**: nothing added past `dig`, `curl`, `ping`, `awk`, `perl`, `openssl` and
      the OS's own tools
- [ ] no changes to `source/app/**` or `releases/**` — the Mac app is frozen at v1.0.0

## notes for the reviewer

<!-- anything that needs a decision, a tradeoff you made, or a thing you could not test -->

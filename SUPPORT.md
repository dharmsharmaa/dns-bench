# support

This is a one-person project. Support is best-effort, and the fastest route is usually to run the
tool's own diagnostics before asking a human.

## where to ask what

| you want | go here |
| --- | --- |
| something is broken | [open a bug report](./.github/ISSUE_TEMPLATE/bug_report.yml) — fill in the template |
| a command should exist, or work differently | [feature request](./.github/ISSUE_TEMPLATE/feature_request.yml) |
| "which resolver is best for me?" | not a support request — see below |
| a security issue | [SECURITY.md](./SECURITY.md) — private channel, not an issue |
| someone behaved badly | [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md) |
| you want to change the code | [CONTRIBUTING.md](./CONTRIBUTING.md) |

## "which resolver is best" is not a support question

It cannot be answered from someone else's machine. Your latency, your path, your ISP's peering and
your router's cache decide it. Anyone who tells you a resolver is "the best" is telling you about
their network.

```sh
dns-bench demo      # what a run looks like, with hardcoded data, no network, no changes
dns-bench -N        # a real run, report only, changes nothing, about 40 seconds
```

`demo` is safe to paste anywhere. `-N` is the real thing: it prints the ranked table and applies
nothing. Read the numbers, run it twice, then decide.

## before you open an issue

```sh
dns-bench doctor    # required tools, versions, and what is missing on this machine
dns-bench version
```

`doctor` exits non-zero when a required dependency is missing, so a failing `doctor` output is
usually the whole answer. Include it. `dns-bench help <command>` prints usage and examples for a
single command, e.g. `dns-bench help ports`.

## redact before you paste

`dns-bench -N` output is genuinely useful in a report, and it also contains **your current DNS
servers, your public IP, your gateway, and sometimes your ISP and city**. Redact those before
posting.

A screenshot of `dns-bench demo` needs no redaction at all. A screenshot of a real run does — look at
the identity lines at the top of the output.

If you are not sure whether something is sensitive: replace it with `<redacted>` and say so. A
report with a hole in it still gets read.

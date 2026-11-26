#!/bin/sh
# dns-bench: DNS benchmark, network diagnostics, domain troubleshooting. macOS + Linux.
# Author: Dharm Sharma (https://dharmsharma.com)
# License: MIT (see LICENSE)
# Run `dns-bench help` for commands.
#
# The shebang is /bin/sh on purpose. The body below is zsh, but naming zsh in
# the shebang makes the kernel fail with a bare "cannot execute: required file
# not found" on any machine without zsh, which is the opposite of helpful. sh
# always exists, so the bootstrap runs, explains the problem, and only then
# execs zsh.

# --- POSIX sh bootstrap ----------------------------------------------------
# Lets `sh dns-bench.zsh` and `bash dns-bench.zsh` work, and offers to install
# zsh when it is missing. This block must stay POSIX-clean: zsh-only syntax
# starts after the `exec` below.
if [ -z "${ZSH_VERSION:-}" ]; then
  # zsh may be installed but off PATH (cron, minimal containers, sudo -i).
  ZSH_BIN=''
  if command -v zsh >/dev/null 2>&1; then
    ZSH_BIN=$(command -v zsh)
  else
    for z in /usr/bin/zsh /usr/local/bin/zsh /bin/zsh /opt/homebrew/bin/zsh /snap/bin/zsh; do
      if [ -x "$z" ]; then ZSH_BIN=$z; break; fi
    done
  fi
  if [ -z "$ZSH_BIN" ]; then
    printf 'dns-bench needs zsh, which is not installed.\n' >&2
    if command -v brew >/dev/null 2>&1; then
      ZSH_INSTALL='brew install zsh'
    elif command -v apt-get >/dev/null 2>&1; then
      ZSH_INSTALL='sudo apt-get update && sudo apt-get install -y zsh'
    elif command -v dnf >/dev/null 2>&1; then
      ZSH_INSTALL='sudo dnf install -y zsh'
    elif command -v yum >/dev/null 2>&1; then
      ZSH_INSTALL='sudo yum install -y zsh'
    elif command -v pacman >/dev/null 2>&1; then
      ZSH_INSTALL='sudo pacman -S --noconfirm zsh'
    elif command -v zypper >/dev/null 2>&1; then
      ZSH_INSTALL='sudo zypper install -y zsh'
    elif command -v apk >/dev/null 2>&1; then
      ZSH_INSTALL='sudo apk add zsh'
    else
      ZSH_INSTALL=''
    fi
    if [ -z "$ZSH_INSTALL" ]; then
      printf 'Install zsh with your package manager, then run this again.\n' >&2
      exit 1
    fi
    printf 'Install it now with: %s ? [Y/n] ' "$ZSH_INSTALL" >&2
    if [ -t 0 ]; then
      read -r ZSH_ANSWER
    elif [ -n "${DNSBENCH_ASSUME_YES:-}" ]; then
      ZSH_ANSWER=y
    else
      printf '\nNot a terminal, so nothing was installed. Run: %s\n' "$ZSH_INSTALL" >&2
      exit 1
    fi
    case "$ZSH_ANSWER" in
      n|N|no|NO)
        printf 'Nothing installed. To use dns-bench later: %s\n' "$ZSH_INSTALL" >&2
        exit 1
        ;;
    esac
    if ! eval "$ZSH_INSTALL"; then
      printf 'zsh installation failed. Try it manually: %s\n' "$ZSH_INSTALL" >&2
      exit 1
    fi
    hash -r 2>/dev/null || true
    printf 'zsh installed.\n' >&2
    ZSH_BIN=''
    if command -v zsh >/dev/null 2>&1; then ZSH_BIN=$(command -v zsh); fi
    if [ -z "$ZSH_BIN" ]; then
      for z in /usr/bin/zsh /usr/local/bin/zsh /bin/zsh /opt/homebrew/bin/zsh /snap/bin/zsh; do
        if [ -x "$z" ]; then ZSH_BIN=$z; break; fi
      done
    fi
    if [ -z "$ZSH_BIN" ]; then
      printf 'zsh is still not on PATH. Open a new shell and run dns-bench again.\n' >&2
      exit 1
    fi
  fi
  exec "$ZSH_BIN" "$0" "$@"
fi
# --- end bootstrap ---------------------------------------------------------

emulate -L zsh

VERSION=3.4.0
SELF=${0:A}
SELF_DIR=${SELF:h}

# Where `dns-bench update` pulls the latest version from.
# Override per run: DNSBENCH_UPDATE_URL=... dns-bench update
UPDATE_URL="${DNSBENCH_UPDATE_URL:-https://raw.githubusercontent.com/dharmsharmaa/dns-bench/main/dns-bench.zsh}"

case "$(uname -s)" in
  Darwin) IS_MAC=1; IS_LINUX=0 ;;
  Linux)  IS_MAC=0; IS_LINUX=1 ;;
  *) print "dns-bench supports macOS and Linux (use dns-bench.ps1 on Windows)."; exit 1 ;;
esac

# ---------- colours ----------
# Respect NO_COLOR and non-TTY. Extended palette shared by help, tables and
# status words; nothing colour-related is ever written to the CSV.
if [[ -t 1 && -z "$NO_COLOR" ]]; then
  C_G=$'\e[32m'; C_Y=$'\e[33m'; C_R=$'\e[31m'
  C_M=$'\e[35m'; C_C=$'\e[36m'; C_W=$'\e[97m'
  C_D=$'\e[2m'; C_B=$'\e[1m'; C_0=$'\e[0m'
else
  C_G=; C_Y=; C_R=; C_M=; C_C=; C_W=; C_D=; C_B=; C_0=
fi
C_OK=$C_G C_ERR=$C_R C_WARN=$C_Y C_DIM=$C_D

hl_names() {   # colour a list of command names: hl_names run best auto
  local n out=
  for n in "$@"; do out+="${out:+, }${C_M}${n}${C_0}"; done
  print -n -- "$out"
}
help_group() { printf "  ${C_W}%-13s${C_0} %s\n" "$1" "$2" }
help_item() {  # help_item USAGE DESCRIPTION EXAMPLE1 EXAMPLE2
  print "${C_M}${1}${C_0}"
  print "  $2"
  print ""
  print "${C_W}Examples${C_0}"
  print "  ${C_C}$3${C_0}"
  print "  ${C_C}$4${C_0}"
}

usage() {
  print "${C_B}dns-bench${C_0} ${C_D}$VERSION${C_0}: benchmark DNS resolvers, check your network, troubleshoot domains."
  print ""
  print "Usage: dns-bench ${C_C}[command]${C_0} [options]"
  print "       dns-bench help ${C_M}<command>${C_0}"
  print ""
  print "${C_W}Commands${C_0}"
  help_group "benchmark"   "$(hl_names run best auto)"
  help_group "dns control" "$(hl_names set reset adblock status list flush)"
  help_group "diagnose"    "$(hl_names info test score)"
  help_group "network"     "$(hl_names speed ports http tls trace asn ptr mtu leak propagation ecs ifaces listen wifi)"
  help_group "maintenance" "$(hl_names install uninstall cron update demo doctor)"
  print ""
  print "${C_D}run is the default: full benchmark, then asks what to apply.${C_0}"
  print "${C_D}help <command> prints usage and examples for one command.${C_0}"
  print ""
  print "${C_W}Options${C_0}"
  cat <<'EOF'
  -d DOMAIN   domain for the cached-latency test (default google.com)
  -n N        samples per resolver, 1-20 (default 5)
  -t K        resolvers in the service test, 1-12 (default 5)
  -x LIST     extra hostnames for the service test, comma separated
  -o FILE     save raw results as CSV to FILE
  --no-csv    don't auto-save a CSV next to the script
  --no-progress  plain output, no progress bar
  -r LIST     (test) extra resolver IPs to compare, comma separated
  -T LIST     (test) record types to show (default A AAAA CNAME NS MX TXT SOA CAA)
  -s          skip the popular-service test
  -c          skip the continent latency test
  -q          quick mode (-s -c, 3 samples, speed phases 4 s); terse for network commands
  -P          privacy: no external ip/geo lookups
  -N          report only, never change dns
  -y          don't ask, apply the best resolver
  --profile P       auto/cron: best or adblock
  --min-gain PCT    auto: only switch if the new score is this much better (default 20)
  --at HH:MM        cron: time of day (default 04:00)
  --system          install into /usr/local/bin with sudo
  --duration SECS   speed: seconds per phase (default 10, -q uses 4)
  --no-upload       speed: skip the upload test

Env: DNSBENCH_JOBS=N        max parallel probes (default 24)
     DNSBENCH_UPDATE_URL=   override the GitHub raw URL used by `update`
     DNSBENCH_CSV_DIR=      where auto-saved CSVs go (default: next to the script)
     DNSBENCH_DEBUG_COLD=1  print generated cold-query names to stderr
     DNSBENCH_ASSUME_YES=1  bootstrap: install a missing zsh without asking
EOF
}

# Per-command help: usage line, one-line description, two runnable examples.
cmd_help_detail() {
  case "$1" in
    run) help_item "dns-bench run [options]" \
      "Full benchmark: cached/cold/jitter/loss, security probes, tables, then apply." \
      "dns-bench run -n 3" "dns-bench run -N -o results.csv" ;;
    best) help_item "dns-bench best" \
      "Quick benchmark and apply the fastest unfiltered resolver." \
      "dns-bench best" "dns-bench best -y" ;;
    auto) help_item "dns-bench auto [--profile best|adblock]" \
      "Unattended run for cron: switch only if the gain clears --min-gain." \
      "dns-bench auto --min-gain 15" "dns-bench auto --profile adblock" ;;
    set) help_item "dns-bench set NAME|#" \
      "Apply a resolver from the list without benchmarking it." \
      "dns-bench set cloudflare" "dns-bench set 4" ;;
    reset) help_item "dns-bench reset" \
      "Return DNS to automatic (DHCP / router) and flush the cache." \
      "dns-bench reset" "sudo dns-bench reset" ;;
    adblock) help_item "dns-bench adblock [off]" \
      "Apply the fastest resolver that verifiably blocks ads (or turn that off)." \
      "dns-bench adblock" "dns-bench adblock off" ;;
    status) help_item "dns-bench status" \
      "Show the DNS in use, the installed copy, and the schedule." \
      "dns-bench status" "dns-bench status -q" ;;
    list) help_item "dns-bench list" \
      "Print every resolver with its row id, kind, region and addresses." \
      "dns-bench list" "dns-bench list | grep -i quad9" ;;
    flush) help_item "dns-bench flush [DOMAIN]" \
      "Flush the local DNS cache (pass a domain to also resolve it after)." \
      "sudo dns-bench flush" "dns-bench flush example.com" ;;
    info) help_item "dns-bench info" \
      "Network info only: addresses, gateway, DNS in use, geo, health checks." \
      "dns-bench info" "dns-bench info -P" ;;
    test) help_item "dns-bench test DOMAIN" \
      "Troubleshoot a domain across resolvers, authoritative NS, DNSSEC, HTTPS." \
      "dns-bench test example.com" "dns-bench test example.com -T 'A MX TXT'" ;;
    speed) help_item "dns-bench speed [--duration N] [--no-upload]" \
      "Latency, jitter, download and upload for the link itself." \
      "dns-bench speed" "dns-bench speed -q" ;;
    ports) help_item "dns-bench ports HOST [PORTS]" \
      "TCP connect test per port; default 22 53 80 443 853 3306 5432 6379 8080." \
      "dns-bench ports 1.1.1.1" "dns-bench ports example.com 80,443,853" ;;
    http) help_item "dns-bench http URL" \
      "HTTP status plus dns/connect/tls/ttfb/total timing, size and redirects." \
      "dns-bench http https://example.com" "dns-bench http http://1.1.1.1/" ;;
    tls) help_item "dns-bench tls HOST[:PORT]" \
      "Certificate subject, issuer, validity, days left, SAN count and protocol." \
      "dns-bench tls example.com" "dns-bench tls example.com:8443" ;;
    trace) help_item "dns-bench trace HOST" \
      "Hop-by-hop path with per-hop RTT (traceroute, tracepath fallback)." \
      "dns-bench trace 1.1.1.1" "dns-bench trace example.com" ;;
    asn) help_item "dns-bench asn HOST|IP" \
      "ASN, prefix, country, registry and org via Team Cymru DNS (no whois)." \
      "dns-bench asn 8.8.8.8" "dns-bench asn example.com" ;;
    ptr) help_item "dns-bench ptr IP" \
      "Reverse DNS plus forward-confirmed reverse DNS (FCrDNS) verdict." \
      "dns-bench ptr 8.8.8.8" "dns-bench ptr 1.1.1.1" ;;
    mtu) help_item "dns-bench mtu HOST" \
      "Path MTU by DF-ping bisection from 1500 down." \
      "dns-bench mtu 1.1.1.1" "dns-bench mtu example.com" ;;
    leak) help_item "dns-bench leak" \
      "Compare your public IP with the egress each resolver sees (DNS leak test)." \
      "dns-bench leak" "dns-bench leak -q" ;;
    propagation) help_item "dns-bench propagation DOMAIN [TYPE]" \
      "Query public resolvers for a record, group identical answers, show agreement." \
      "dns-bench propagation example.com" "dns-bench propagation example.com MX" ;;
    ecs) help_item "dns-bench ecs [HOST]" \
      "Show whether EDNS Client Subnet changes the answer (subnet=0 vs subnet=<ip>/24)." \
      "dns-bench ecs" "dns-bench ecs example.com" ;;
    ifaces) help_item "dns-bench ifaces" \
      "Interface state, MTU, MAC, IPv4, IPv6 and media. No DNS queries." \
      "dns-bench ifaces" "dns-bench ifaces -q" ;;
    listen) help_item "dns-bench listen" \
      "Listening TCP sockets with the owning process (lsof, netstat fallback)." \
      "dns-bench listen" "sudo dns-bench listen" ;;
    wifi) help_item "dns-bench wifi" \
      "SSID, BSSID, channel, band, signal, noise, tx rate and security." \
      "dns-bench wifi" "dns-bench wifi -q" ;;
    score) help_item "dns-bench score [--no-upload] [-q]" \
      "One graded score for this connection: DNS, latency, throughput, privacy, stability." \
      "dns-bench score" "dns-bench score -q --no-upload" ;;
    doctor) help_item "dns-bench doctor" \
      "Dependency, privilege, install, schedule, log and version checklist. Exits 1 if a required tool is missing." \
      "dns-bench doctor" "dns-bench doctor -q" ;;
    install) help_item "dns-bench install [--system]" \
      "Copy this script into PATH as dns-bench." \
      "dns-bench install" "sudo dns-bench install --system" ;;
    uninstall) help_item "dns-bench uninstall" \
      "Remove the installed command and the schedule." \
      "dns-bench uninstall" "sudo dns-bench uninstall" ;;
    cron) help_item "dns-bench cron WHEN|off [--at HH:MM] [--profile P]" \
      "Schedule auto runs: hourly, 6h, daily, weekly, 2d, or a cron expression." \
      "dns-bench cron daily --at 04:30" "dns-bench cron off" ;;
    update) help_item "dns-bench update [--check]" \
      "Pull the latest script from GitHub (or only check whether one exists)." \
      "dns-bench update" "dns-bench update --check" ;;
    demo) help_item "dns-bench demo" \
      "Print a full sample run with fake data. No network, no changes." \
      "dns-bench demo" "dns-bench demo -q" ;;
    version) help_item "dns-bench version" \
      "Print the version and exit." \
      "dns-bench version" "dns-bench --version" ;;
    help) help_item "dns-bench help [command]" \
      "List commands by group, or show usage and examples for one command." \
      "dns-bench help" "dns-bench help ports" ;;
    *) return 1 ;;
  esac
}

# Closest command by prefix, then substring, then first letter.
suggest_cmd() {
  local want=$1 c
  for c in $KNOWN_CMDS; do [[ "$c" == "$want"* ]] && { print -r -- "$c"; return; }; done
  for c in $KNOWN_CMDS; do [[ "$c" == *"$want"* ]] && { print -r -- "$c"; return; }; done
  for c in $KNOWN_CMDS; do [[ "$c[1]" == "$want[1]" ]] && { print -r -- "$c"; return; }; done
}

zparseopts -D -E -- d:=o_d n:=o_n t:=o_t x:=o_x o:=o_o r:=o_r T:=o_T N=o_N P=o_P s=o_s c=o_c q=o_q y=o_y h=o_h \
  -help=o_h -version=o_ver -system=o_sys -profile:=o_prof -min-gain:=o_gain -at:=o_at \
  -no-csv=o_nocsv -no-progress=o_noprog -duration:=o_dur -no-upload=o_noul || { usage; exit 1 }
(( $#o_h )) && { usage; exit 0 }
(( $#o_ver )) && { print "dns-bench $VERSION"; exit 0 }

KNOWN_CMDS=(run info test best adblock set reset flush status list speed demo auto install uninstall cron update version help
  ports http tls trace asn ptr leak propagation mtu ecs ifaces listen wifi doctor score)
CMD=run
DOMAIN_ARG=
if [[ -n "$1" ]]; then
  if (( ${KNOWN_CMDS[(Ie)$1]} )); then CMD=$1; shift
  elif [[ "$1" == *.* ]]; then DOMAIN_ARG=$1; shift
  else
    local _sug=$(suggest_cmd "$1")
    print -u2 "${C_ERR}Unknown command:${C_0} $1"
    [[ -n "$_sug" ]] && print -u2 "Did you mean ${C_M}$_sug${C_0}?  Try: dns-bench help $_sug"
    print -u2 "Run 'dns-bench help' to see every command."
    exit 1
  fi
fi
if [[ $CMD == help ]]; then
  if [[ -n "$1" ]]; then
    cmd_help_detail "$1" || {
      local _sug=$(suggest_cmd "$1")
      print -u2 "${C_ERR}No help for:${C_0} $1"
      [[ -n "$_sug" ]] && print -u2 "Did you mean ${C_M}$_sug${C_0}?  Try: dns-bench help $_sug"
      exit 1
    }
  else
    usage
  fi
  exit 0
fi
[[ $CMD == version ]] && { print "dns-bench $VERSION"; exit 0 }

DOMAIN="${o_d[-1]:-${DOMAIN_ARG:-google.com}}"
SAMPLES="${o_n[-1]:-5}"
TOPK="${o_t[-1]:-5}"
EXTRA_SVC="${o_x[-1]}"
CSV_OUT="${o_o[-1]}"
EXTRA_RES="${o_r[-1]}"
REC_TYPES="${o_T[-1]:-A AAAA CNAME NS MX TXT SOA CAA}"
SKIP_SVC=$#o_s; SKIP_GEO=$#o_c; NO_APPLY=$#o_N; NO_EXT=$#o_P; ASSUME_YES=$#o_y
(( $#o_q )) && { SKIP_SVC=1; SKIP_GEO=1; SAMPLES=3 }
MAXJOBS="${DNSBENCH_JOBS:-24}"
QUIET=0; FAST=0; TERSE=$#o_q
CSV_AUTO=1; (( $#o_nocsv )) && CSV_AUTO=0
PROGRESS_TTY=0; [[ -t 1 ]] && PROGRESS_TTY=1
(( $#o_noprog )) && PROGRESS_TTY=0

SPEED_SECS="${o_dur[-1]:-10}"
SPEED_UPLOAD=1; (( $#o_noul )) && SPEED_UPLOAD=0
(( $#o_q )) && [[ -z "${o_dur[-1]}" ]] && SPEED_SECS=4
[[ "$SPEED_SECS" == <2-60> ]] || { print -u2 "dns-bench: --duration must be 2-60 seconds."; exit 1 }

[[ "$DOMAIN" =~ '^[A-Za-z0-9._-]+$' ]] || { print "Invalid domain."; exit 1 }
[[ "$SAMPLES" == <1-20> ]]  || { print "Samples (-n) must be 1-20."; exit 1 }
[[ "$TOPK" == <1-12> ]]     || { print "Top-K (-t) must be 1-12."; exit 1 }
[[ "$MAXJOBS" == <1-200> ]] || MAXJOBS=24

die()  { print -u2 "${C_ERR}dns-bench:${C_0} $*"; exit 1 }
warn() { (( QUIET )) || print -u2 "  ${C_WARN}warning:${C_0} $*" }

need() { command -v "$1" >/dev/null 2>&1 }
# doctor exists to report a broken environment, so it must run before the gate.
if [[ $CMD != doctor ]]; then
  if ! need dig; then
    if (( IS_LINUX )); then die "dig not found. install it: apt install dnsutils | dnf install bind-utils | pacman -S bind | apk add bind-tools"
    else die "dig not found (it normally ships with macOS)"; fi
  fi
  for bin in curl perl awk sort; do need $bin || die "missing dependency: $bin"; done
  if (( IS_MAC )); then
    for bin in networksetup scutil route ipconfig ifconfig; do need $bin || die "missing dependency: $bin"; done
  else
    need ip || die "missing dependency: ip (iproute2)"
  fi
  need ping || die "missing dependency: ping"
fi

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT INT TERM

section() { print "\n${C_B}${C_C}== $1 ==${C_0}" }
kv()      { printf "  %-26s %s\n" "$1" "$2" }
note()    { print "  ${C_D}$1${C_0}" }
cell()    { local t=${1[1,$2]}; print -n -- "${3}${(r:$2:)t}${C_0}" }   # cell TEXT WIDTH [COLOUR]
is_num()  { [[ "$1" == <-> || "$1" == <->.<-> ]] }
jget()    { perl -0777 -ne 'BEGIN{$k=shift @ARGV} if (/"\Q$k\E"\s*:\s*"([^"]*)"/) {print $1} elsif (/"\Q$k\E"\s*:\s*(-?[0-9.]+)/) {print $1}' "$2" "$1" }   # jget FILE KEY

SUDO=(sudo); (( EUID == 0 )) && SUDO=()
run_root() { "${SUDO[@]}" "$@" }

ms_cell() {   # ms_cell VALUE WIDTH
  local v=$1 w=$2 col txt
  if is_num "$v"; then
    txt="$v ms"
    if (( v < 25 )); then col=$C_G; elif (( v < 60 )); then col=$C_Y; else col=$C_R; fi
  elif [[ "$v" == (Timeout|TIMEOUT) ]]; then txt=$v; col=$C_R
  else txt=$v; col=$C_D; fi
  cell "$txt" $w "$col"
}
yn_cell() {   # yn_cell VALUE WIDTH GOODVALUE
  local v=$1 w=$2 good=$3 col=$C_D
  [[ "$v" == "$good" ]] && col=$C_G
  [[ "$v" == HIJACK || ( "$v" == no && "$good" == yes ) ]] && col=$C_R
  [[ "$v" == "?" || "$v" == "-" || "$v" == N/A ]] && col=$C_D
  cell "$v" $w "$col"
}

# ---------- progress bar ----------
typeset -gi PB_ON=0 PB_TOTAL=0 PB_WIDTH=30 PB_T0=0
PB_LABEL=

pb_start() {   # pb_start TOTAL LABEL
  PB_TOTAL=$1; PB_LABEL=$2; PB_T0=$SECONDS; PB_ON=0
  (( PROGRESS_TTY && ! QUIET )) || return 0
  (( PB_TOTAL > 0 )) || return 0
  PB_ON=1
  PB_WIDTH=$(( ${COLUMNS:-80} - 42 ))
  (( PB_WIDTH > 30 )) && PB_WIDTH=30
  (( PB_WIDTH < 8 )) && PB_WIDTH=8
  rm -f "$TMP/pb.stop"
  pb_render 0
}

pb_render() {   # pb_render DONE
  (( PB_ON )) || return 0
  local done=${1:-0} pct fill empty
  (( done > PB_TOTAL )) && done=$PB_TOTAL
  pct=$(( done * 100 / PB_TOTAL ))
  fill=$(( done * PB_WIDTH / PB_TOTAL ))
  empty=$(( PB_WIDTH - fill ))
  printf '\r  %-22s [%s%s] %3d%% %d/%d %3ds' "$PB_LABEL" \
    "${(l:$fill::#:)}" "${(l:$empty::-:)}" "$pct" "$done" "$PB_TOTAL" "$(( SECONDS - PB_T0 ))"
}

pb_watch() {   # pb_watch PREFIX   (background: counts finished files starting with PREFIX)
  setopt local_options null_glob
  local prefix=$1
  local -a f
  while [[ ! -f "$TMP/pb.stop" ]]; do
    f=($prefix*)
    pb_render ${#f}
    kill -0 $PPID 2>/dev/null || break
    sleep 0.2
  done
}

pb_stop() {   # pb_stop [WATCH_PID]
  (( PB_ON )) || return 0
  : > "$TMP/pb.stop"
  [[ -n "$1" ]] && wait "$1" 2>/dev/null
  pb_render $PB_TOTAL
  print
  PB_ON=0
}

# =====================================================================
# low-level probes
# =====================================================================
COLD_TLDS=(com net org)

# --- cold-query naming ------------------------------------------------------
# A "cold" number is only meaningful if the name really was uncached. Forked
# probe workers inherit the parent's $RANDOM state, so without an explicit
# reseed every resolver would be asked the identical three names. That is not
# merely wasteful: Verisign and Neustar both front the UltraDNS backend, so a
# name warmed by one probe can be answered from cache moments later by another.
# Cache reuse would flatter the score, which is the one bug class this tool
# cannot afford. Hence: reseed per worker, and make every cold name unique per
# resolver AND per run (run salt + resolver index + sample index).
zmodload zsh/datetime 2>/dev/null
RUN_SALT=
make_run_salt() {
  local digits=0123456789abcdefghijklmnopqrstuvwxyz n out=
  local us=${EPOCHREALTIME//[^0-9]/}
  us=${us[-15,-1]}                    # keep the low digits: EPOCHREALTIME has 20
  [[ "$us" == <-> ]] || us=$(( $(date +%s) * 1000000 ))
  n=$(( (us + ${sysparams[pid]:-$$} * 97) % 2176782336 ))   # 36^6
  (( n < 0 )) && n=$(( -n ))
  while (( n > 0 )); do out="${digits[$(( n % 36 + 1 ))]}$out"; n=$(( n / 36 )); done
  print -r -- "${out:-0}"
}
RUN_SALT=$(make_run_salt)

# Reseed the per-worker RNG from high-resolution time, pid and resolver index.
seed_probe_rng() {   # seed_probe_rng RESOLVER_IDX
  local us=${EPOCHREALTIME//[^0-9]/}
  us=${us[-15,-1]}
  [[ "$us" == <-> ]] || us=$(( $(date +%s) * 1000000 ))
  RANDOM=$(( (us + ${sysparams[pid]:-$$} * 31 + $1 * 7919) % 32768 ))
}

cold_name() {   # cold_name RESOLVER_IDX SAMPLE_IDX
  local tld=${COLD_TLDS[$(( RANDOM % 3 + 1 ))]}
  print -r -- "cold-${RUN_SALT}-r${1}-${2}.${tld}"
}

cold_trace() {  # DNSBENCH_DEBUG_COLD=1 prints every generated name to stderr
  [[ -n "$DNSBENCH_DEBUG_COLD" && "$DNSBENCH_DEBUG_COLD" != 0 ]] && print -u2 "cold-name $1"
  return 0
}

# tcp_ms HOST PORT [TIMEOUT] -> prints ms, returns 1 on failure
tcp_ms() {
  local out
  out=$(perl -MIO::Socket::IP -MTime::HiRes=time -e '$t=time; $s=IO::Socket::IP->new(PeerHost=>$ARGV[0],PeerPort=>$ARGV[1],Timeout=>$ARGV[2]) or exit 1; printf "%d",(time-$t)*1000+0.5' "$1" "$2" "${3:-3}" 2>/dev/null) || { print fail; return 1 }
  print "$out"
}

# dns_stats IP cached|cold COUNT [RESOLVER_IDX] -> "median min max loss%"
dns_stats() {
  local ip=$1 mode=$2 n=$3 idx=${4:-0} i q out ms fails=0 tries valid
  local -a t
  [[ "$ip" == none ]] && { print "N/A - - -"; return }
  tries=$n; [[ $mode == cached ]] && tries=$(( n + 1 ))
  for (( i = 1; i <= tries; i++ )); do
    if [[ $mode == cold ]]; then q=$(cold_name "$idx" "$i"); cold_trace "$q"; else q=$DOMAIN; fi
    out=$(dig @"$ip" "$q" A +tries=1 +time=2 +stats 2>/dev/null)
    valid=0
    if [[ $mode == cold ]]; then
      [[ "$out" == *"status: NXDOMAIN"* || "$out" == *"status: NOERROR"* ]] && valid=1
    else
      [[ "$out" == *"status: NOERROR"* && "$out" == *"ANSWER: "[1-9]* ]] && valid=1
    fi
    [[ $mode == cached && $i == 1 ]] && continue
    if (( valid )); then
      ms=$(print -r -- "$out" | awk '/Query time:/ {print $4; exit}')
      if [[ "$ms" == <-> ]]; then t+=($ms); else (( fails++ )); fi
    else
      (( fails++ ))
    fi
  done
  (( ${#t} )) || { print "Timeout - - 100"; return }
  t=(${(on)t})
  print "${t[$(( (${#t} + 1) / 2 ))]} ${t[1]} ${t[-1]} $(( fails * 100 / n ))"
}

# ping_stats IP 4|6 -> "avg_ms loss%"
ping_stats() {
  local ip=$1 fam=$2 out avg loss
  [[ "$ip" == none || -z "$ip" ]] && { print "N/A -"; return }
  if (( IS_MAC )); then
    if [[ $fam == 6 ]]; then out=$(perl -e 'alarm shift; exec @ARGV' 7 ping6 -c 3 "$ip" 2>&1)
    else out=$(ping -c 3 -t 5 "$ip" 2>&1); fi
  else
    if [[ $fam == 6 ]]; then out=$(ping -6 -c 3 -W 2 "$ip" 2>&1 || ping6 -c 3 -W 2 "$ip" 2>&1)
    else out=$(ping -c 3 -W 2 "$ip" 2>&1); fi
  fi
  loss=$(print -r -- "$out" | grep -oE '[0-9.]+% packet loss' | grep -oE '^[0-9.]+')
  avg=$(print -r -- "$out" | awk -F= '/min\/avg\/max/ {split($2,a,"/"); print a[2]; exit}')
  if [[ -n "$avg" ]]; then printf "%.1f %s\n" "$avg" "${loss:-0}"; else print "Timeout 100"; fi
}

# ping_detail HOST -> "avg jitter loss"   (jitter = stddev/mdev from ping)
ping_detail() {
  local out avg jit loss
  if (( IS_MAC )); then out=$(ping -c 5 -t 3 "$1" 2>&1)
  else out=$(ping -c 5 -W 2 "$1" 2>&1); fi
  loss=$(print -r -- "$out" | grep -oE '[0-9.]+% packet loss' | grep -oE '^[0-9.]+')
  read -r avg jit <<< "$(print -r -- "$out" | awk -F= '/min\/avg\/max/ {split($2,a,"/"); print a[2], a[4]+0; exit}')"
  [[ -n "$avg" ]] || { print "Timeout 0 100"; return }
  printf "%.1f %.1f %s\n" "$avg" "${jit:-0}" "${loss:-0}"
}

# =====================================================================
# speed test
# =====================================================================
zmodload zsh/datetime 2>/dev/null
SPEED_STREAMS=4
SPEED_DL_BYTES=50000000      # Cloudflare rejects anything larger
SPEED_UP_MB=8
SPEED_MIRROR_USED=
SPEED_HTTP_NOTE=
SPEED_UPLOAD_NOTE=

speed_now() {
  if [[ -n "$EPOCHREALTIME" && "$EPOCHREALTIME" == <->.<-> ]]; then
    print -r -- "$EPOCHREALTIME"
  else
    perl -MTime::HiRes=time -e 'printf "%.6f\n", time'
  fi
}

file_bytes() {
  local n
  [[ -f "$1" ]] || { print 0; return }
  if (( IS_MAC )); then n=$(stat -f%z "$1" 2>/dev/null) else n=$(stat -c%s "$1" 2>/dev/null) fi
  print "${n:-0}"
}

speed_line() {   # speed_line LABEL MBPS MB SECS
  local label=$1 mbps=$2 mb=$3 secs=$4
  printf "  %-24s %s%s Mbps%s  %s(%s MB in %ss)%s\n" "$label" \
    "$C_B" "$(printf '%.1f' $mbps)" "$C_0" "$C_D" "$(printf '%.0f' $mb)" "$(printf '%.1f' $secs)" "$C_0"
}

speed_meter() {   # speed_meter LABEL ELAPSED TOTAL MBPS MB
  (( PROGRESS_TTY )) || return 0
  local label=$1 elapsed=$2 total=$3 mbps=$4 mb=$5 width=24 fill empty
  (( total > 0 )) || total=1
  fill=$(( elapsed * width / total )); (( fill > width )) && fill=$width
  empty=$(( width - fill ))
  printf '\r  %-10s [%s%s] %6.1f Mbps %5.0f MB' "$label" "${(l:$fill::#:)}" "${(l:$empty::-:)}" "$mbps" "$mb" >&2
}

# speed_download SECONDS -> "mbps mb secs mirror"  (or "fail")
# Mirrors are tried in order; Cloudflare rate-limits (HTTP 429) bursty use, so
# OVH is the fallback. Only HTTP 200 responses count.
speed_download() {
  setopt local_options null_glob typeset_silent
  local dur=$1 mirror name url round i size code httpstat codes
  local t0 prev_t prev_b now alive f p u secs
  local -a pids files stats
  typeset -F mbps=0 live=0
  local best_mbps=0 best_mb=0 best_secs=0 best_name= have=0
  for mirror in \
    "cloudflare|https://speed.cloudflare.com/__down?bytes=$SPEED_DL_BYTES&r=%R%" \
    "ovh|https://proof.ovh.net/files/100Mb.dat?r=%R%"; do
    name=${mirror%%|*}; url=${mirror#*|}
    for round in 1 2; do
      rm -f "$TMP/speed.dl."*(N)
      pids=(); files=(); stats=()
      for (( i = 1; i <= SPEED_STREAMS; i++ )); do
        u=${url//\%R\%/$RANDOM$i}
        curl -4 -sL --max-time "$dur" -o "$TMP/speed.dl.$i" \
          -w '%{size_download} %{http_code}' "$u" > "$TMP/speed.dl.$i.stat" 2>/dev/null &
        pids+=($!)
        files+=("$TMP/speed.dl.$i")
        stats+=("$TMP/speed.dl.$i.stat")
      done
      t0=$(speed_now); prev_t=$t0; prev_b=0
      while true; do
        now=$(speed_now); size=0
        for f in "${files[@]}"; do size=$(( size + $(file_bytes "$f") )); done
        alive=0
        for p in "${pids[@]}"; do kill -0 "$p" 2>/dev/null && alive=1; done
        live=0
        (( now > prev_t )) && live=$(( (size - prev_b) * 8 / (now - prev_t) / 1000000 ))
        speed_meter "Download" $(( now - t0 )) "$dur" "$live" $(( size / 1048576 ))
        (( alive )) || break
        prev_t=$now; prev_b=$size
        sleep 0.2
      done
      wait "${pids[@]}" 2>/dev/null
      now=$(speed_now); secs=$(( now - t0 ))
      size=0; codes=""
      for i in "${stats[@]}"; do
        read -r code httpstat <<< "$(cat "$i" 2>/dev/null)"
        size=$(( size + ${code:-0} ))
        codes+=" ${httpstat:-0}"
      done
      if (( PROGRESS_TTY )) && (( size > 0 && secs > 0.05 )); then
        speed_meter "Download" "$dur" "$dur" $(( size * 8 / secs / 1000000 )) $(( size / 1048576 ))
      fi
      # a working mirror answers 200 with real bytes; retry once for a transient blip
      if [[ "$codes" != *" 200"* ]]; then
        speed_note_http "$name" "$codes"
        (( round == 1 )) && { sleep 1; continue }
        break
      fi
      (( secs > 0.05 && size > 1048576 )) || break
      mbps=$(( size * 8 / secs / 1000000 ))
      have=1
      if (( mbps > best_mbps )); then
        best_mbps=$(( mbps )); best_mb=$(( size / 1048576 )); best_secs=$secs; best_name=$name
      fi
      # a fast link finishes early: run one warm round and keep the better number
      (( secs < dur * 0.7 )) || break
    done
    (( have )) && break
  done
  (( have )) || { print "fail|$SPEED_HTTP_NOTE"; return 1; }
  print "$(printf '%.1f' $best_mbps) $best_mb $best_secs ${best_name}|$SPEED_HTTP_NOTE"
}

# speed_note_http MIRROR CODES -> records why a mirror was skipped
speed_note_http() {
  local name=$1 codes=$2
  if [[ "$codes" == *" 429"* ]]; then
    SPEED_HTTP_NOTE="rate-limited (HTTP 429)"
  elif [[ "$codes" == *" 403"* ]]; then
    SPEED_HTTP_NOTE="refused the request (HTTP 403)"
  elif [[ -n "${codes// /}" && "$codes" != *" 000"* ]]; then
    SPEED_HTTP_NOTE="HTTP$(print -r -- "$codes" | tr -s ' ' | sed 's/^ //')"
  fi
}

# speed_upload SECONDS -> "mbps mb secs"  (or "fail")
speed_upload() {
  setopt local_options null_glob typeset_silent
  local dur=$1 i size code p t0 now secs mbps codes="" rate=0
  local -a pids
  local upfile="$TMP/speed.up.bin"
  (( $(file_bytes "$upfile") == SPEED_UP_MB * 1048576 )) || \
    dd if=/dev/zero of="$upfile" bs=1048576 count=$SPEED_UP_MB 2>/dev/null || return 1
  rm -f "$TMP/speed.up.out."*(N)
  pids=()
  t0=$(speed_now)
  for (( i = 1; i <= 3; i++ )); do
    curl -4 -s --max-time "$dur" -X POST --data-binary "@$upfile" \
      -H 'Content-Type: application/octet-stream' -o /dev/null \
      -w '%{size_upload} %{http_code}' "https://speed.cloudflare.com/__up" > "$TMP/speed.up.out.$i" 2>/dev/null &
    pids+=($!)
  done
  (( PROGRESS_TTY )) && print -n "  Upload                   measuring" >&2
  while true; do
    local alive=0
    for p in "${pids[@]}"; do kill -0 "$p" 2>/dev/null && alive=1; done
    (( alive )) || break
    (( PROGRESS_TTY )) && printf '.' >&2 && sleep 0.6
    (( PROGRESS_TTY )) || sleep 0.2
  done
  wait "${pids[@]}" 2>/dev/null
  now=$(speed_now); secs=$(( now - t0 ))
  (( PROGRESS_TTY )) && print >&2
  size=0
  for i in "$TMP/speed.up.out."*(N); do
    read -r code rate <<< "$(cat "$i" 2>/dev/null)"
    size=$(( size + ${code:-0} ))
    codes+=" ${rate:-0}"
  done
  [[ "$codes" == *" 429"* ]] && SPEED_UPLOAD_NOTE="Cloudflare is rate-limiting uploads (HTTP 429); retry in a minute"
  (( secs > 0.05 && size > 262144 )) || { print "fail|$SPEED_UPLOAD_NOTE"; return 1; }
  mbps=$(( size * 8 / secs / 1000000 ))
  print "$(printf '%.1f' $mbps) $(( size / 1048576 )) $(printf '%.1f' $secs)"
}

speed_csv() {   # speed_csv LAT_AVG LAT_JIT LAT_LOSS DL UL
  local f=$CSV_OUT
  [[ -n "$f" ]] || return 0
  {
    print "metric,value,unit"
    print "latency_avg,$1,ms"
    print "latency_jitter,$2,ms"
    print "latency_loss,$3,%"
    [[ "$4" != fail* ]] && print "download_avg,$(print -r -- "$4" | cut -d' ' -f1),mbps"
    [[ "$5" != fail* ]] && print "upload_avg,$(print -r -- "$5" | cut -d' ' -f1),mbps"
  } > "$f" && print "  Results saved to ${C_B}$f${C_0}"
}

cmd_speed() {
  detect_net
  [[ -n "$ACTIVE_DEV" ]] || die "no default route: you appear to be offline"
  need curl || die "curl is required for the speed test"
  section "Speed test"
  note "Cloudflare edge (OVH fallback), $SPEED_STREAMS parallel streams, IPv4. Measures the link itself, not your DNS choice."

  local lat jit loss dl ul target lat_target= have_lat=0
  for target in 1.1.1.1 8.8.8.8; do
    read -r lat jit loss <<< "$(ping_detail "$target")"
    [[ "$lat" == Timeout ]] && continue
    have_lat=1; lat_target=$target
    printf "  %-24s %s%s ms%s  %s(jitter %s ms, %s%% loss)%s\n" "Latency to $target" \
      "$C_B" "$lat" "$C_0" "$C_D" "$jit" "${loss%.0}" "$C_0"
    break
  done
  if (( ! have_lat )); then
    lat=0; jit=0; loss=100
    warn "latency probe failed (ICMP blocked or offline)"
  fi

  local dl_mbps dl_mb dl_secs dl_mirror dl_note dl_rest
  dl=$(speed_download "$SPEED_SECS")
  (( PROGRESS_TTY )) && print
  if [[ "$dl" == fail* ]]; then
    dl_note=${dl#*|}
    if [[ -n "$dl_note" ]]; then warn "download test failed: $dl_note"
    else warn "download test failed (every mirror unreachable)"; fi
  else
    dl_mbps=${dl%% *}; dl_rest=${dl#* }
    dl_mb=${dl_rest%% *}; dl_rest=${dl_rest#* }
    dl_secs=${dl_rest%% *}; dl_rest=${dl_rest#* }
    dl_mirror=${dl_rest%%|*}; dl_note=${dl_rest#*|}
    speed_line "Download" "$dl_mbps" "$dl_mb" "$dl_secs"
    if [[ "$dl_mirror" != cloudflare ]]; then
      note "Cloudflare unavailable: ${dl_note:-no answer}; measured against the OVH mirror."
    fi
  fi

  if (( SPEED_UPLOAD )); then
    ul=$(speed_upload "$SPEED_SECS")
    if [[ "$ul" == fail* ]]; then
      local ul_note=${ul#*|}
      warn "upload test failed${ul_note:+: $ul_note}"
    else
      speed_line "Upload" "$(print -r -- "$ul" | cut -d' ' -f1)" "$(print -r -- "$ul" | cut -d' ' -f2)" "$(print -r -- "$ul" | cut -d' ' -f3)"
    fi
  else
    ul=fail
    note "Upload skipped (--no-upload)."
  fi

  local dln=${dl%% *} uln=${ul%% *} ratio
  if is_num "$dln" && is_num "$uln" && (( uln > 0 )) && [[ "${dl_mirror:-cloudflare}" == cloudflare ]]; then
    ratio=$(printf '%.1f' $(( dln / uln )))
    if (( dln / uln >= 5 )); then
      note "Download is ${ratio}x upload. Typical for home fibre/cable."
    elif (( dln / uln >= 2 )); then
      note "Download is ${ratio}x upload."
    else
      note "Download is ${ratio}x upload: effectively a symmetric link."
    fi
  fi
  (( have_lat )) && [[ "$lat_target" != 1.1.1.1 ]] && note "1.1.1.1 did not answer ping; latency above is to $lat_target."
  speed_csv "$lat" "$jit" "$loss" "$dl" "$ul"
  note "Run it twice; Wi-Fi and background traffic move the numbers. Compare with: dns-bench speed -q"
}

# ---------- feature / security tests (take the resolver IP) ----------
t_dnssec() {
  local ok bad
  ok=$(dig @"$1" sigok.verteiltesysteme.net A +tries=1 +time=3 2>/dev/null)
  bad=$(dig @"$1" sigfail.verteiltesysteme.net A +tries=1 +time=3 2>/dev/null)
  if   [[ "$ok" == *"status: NOERROR"* && "$bad" == *"status: SERVFAIL"* ]]; then print yes
  elif [[ "$ok" == *"status: NOERROR"* && "$bad" == *"status: NOERROR"*  ]]; then print no
  else print "?"; fi
}
t_nx() {
  local out q tld=${COLD_TLDS[$(( RANDOM % 3 + 1 ))]}
  q="nx-${RUN_SALT}-r${2:-0}.${tld}"   # unique per resolver and run, like the cold names
  cold_trace "$q"
  out=$(dig @"$1" "$q" A +tries=1 +time=3 2>/dev/null)
  if   [[ "$out" == *"status: NXDOMAIN"* ]]; then print ok
  elif [[ "$out" == *"status: NOERROR"*  ]]; then print HIJACK
  else print "?"; fi
}
t_tcp()  { [[ "$(dig @"$1" +tcp "$DOMAIN" A +tries=1 +time=3 2>/dev/null)" == *"status: NOERROR"* ]] && print yes || print no }
t_port() { tcp_ms "$1" "$2" 2 >/dev/null && print yes || print no }
# ad-block check: majority of 3 well-known ad domains refused / null-routed
t_ads() {
  local d out ans blocked=0 seen=0
  for d in doubleclick.net googleadservices.com pagead2.googlesyndication.com; do
    out=$(dig @"$1" "$d" A +tries=1 +time=3 2>/dev/null)
    [[ "$out" == *"timed out"* || -z "$out" ]] && continue
    (( seen++ ))
    ans=$(print -r -- "$out" | awk '$0 !~ /^;/ && $3=="IN" && $4=="A" {print $5; exit}')
    if [[ "$out" == *"status: NXDOMAIN"* || "$out" == *"status: REFUSED"* || "$ans" == (0.0.0.0|127.0.0.1|146.112.61.*) || ( -z "$ans" && "$out" == *"status: NOERROR"* ) ]]; then (( blocked++ )); fi
  done
  (( seen == 0 )) && { print "?"; return }
  (( blocked * 2 > seen )) && print yes || print no
}
t_pop() {
  local ip=$1 name=$2 r q
  if [[ "$name" == OpenDNS* ]]; then
    r=$(dig @"$ip" TXT debug.opendns.com +short +tries=1 +time=2 2>/dev/null | tr -d '"' | awk '/^server /{print $2; exit}')
    [[ -n "$r" ]] && { print -r -- "$r"; return }
  fi
  for q in id.server hostname.bind; do
    r=$(dig @"$ip" CH TXT $q +short +tries=1 +time=2 2>/dev/null | tr -d '"' | head -1)
    if [[ -n "$r" && "$r" != *"timed out"* && "$r" != ";"* && "$r" != *" "*" "* ]]; then print -r -- "${r[1,22]//|/_}"; return; fi
  done
  print -- "-"
}

# =====================================================================
# platform layer: network detection
# =====================================================================
dev_to_service() {
  if (( IS_MAC )); then
    networksetup -listallhardwareports | awk -v dev="$1" '/Hardware Port:/ {p=$0; sub(/Hardware Port: /,"",p)} /Device:/ && $2==dev {print p; exit}'
  else
    local c=
    if need nmcli; then c=$(nmcli -g GENERAL.CONNECTION device show "$1" 2>/dev/null | head -1); fi
    [[ "$c" == "--" ]] && c=
    print -r -- "${c:-$1}"
  fi
}

sys_dns_list() {   # IPv4 servers the system is really using
  local out=
  if (( IS_MAC )); then
    scutil --dns 2>/dev/null | awk '/^resolver #1$/{f=1;next} /^resolver #/{f=0} f && /nameserver\[/ {print $3}'
  else
    if need resolvectl; then
      out=$(resolvectl dns "$ACTIVE_DEV" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}')
      [[ -z "$out" ]] && out=$(resolvectl dns 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}')
    fi
    [[ -z "$out" ]] && out=$(awk '/^nameserver/ {print $2}' /etc/resolv.conf 2>/dev/null)
    print -r -- "$out"
  fi
}

detect_net() {
  DEF_DEV=; GATEWAY=; TUNNEL=0; ACTIVE_DEV=; ACTIVE_SERVICE=; LOCAL4=; GLOBAL6=(); SYS_DNS=(); GW_DNS=0; HAS_V6=0
  local line d g
  if (( IS_MAC )); then
    DEF_DEV=$(route -n get default 2>/dev/null | awk '/interface:/ {print $2; exit}')
    GATEWAY=$(route -n get default 2>/dev/null | awk '/gateway:/ {print $2; exit}')
    ACTIVE_DEV=$DEF_DEV
    if [[ "$DEF_DEV" == (utun*|ipsec*|ppp*) ]]; then
      TUNNEL=1
      for d in ${(f)"$(networksetup -listallhardwareports | awk '/Device:/ {print $2}')"}; do
        [[ -n "$(ipconfig getifaddr $d 2>/dev/null)" ]] && { ACTIVE_DEV=$d; break }
      done
      GATEWAY=$(route -n get -ifscope $ACTIVE_DEV default 2>/dev/null | awk '/gateway:/ {print $2; exit}')
    fi
    LOCAL4=$(ipconfig getifaddr "$ACTIVE_DEV" 2>/dev/null)
    GLOBAL6=(${(f)"$(ifconfig "$ACTIVE_DEV" inet6 2>/dev/null | awk '/inet6 / && $2 !~ /^fe80/ {print $2}')"})
  else
    local first=1
    while IFS= read -r line; do
      d=$(print -r -- "$line" | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}')
      g=$(print -r -- "$line" | awk '{for(i=1;i<=NF;i++) if($i=="via") print $(i+1)}')
      [[ -z "$d" ]] && continue
      if (( first )); then DEF_DEV=$d; ACTIVE_DEV=$d; GATEWAY=$g; first=0; fi
      if [[ "$d" != (tun*|wg*|ppp*|tailscale*|zt*|vpn*|ipsec*|utun*) ]]; then ACTIVE_DEV=$d; GATEWAY=$g; break; fi
    done < <(ip -4 route show default 2>/dev/null)
    [[ "$ACTIVE_DEV" != "$DEF_DEV" ]] && TUNNEL=1
    LOCAL4=$(ip -4 -o addr show dev "$ACTIVE_DEV" 2>/dev/null | awk '{sub(/\/.*/,"",$4); print $4; exit}')
    GLOBAL6=(${(f)"$(ip -6 -o addr show dev "$ACTIVE_DEV" scope global 2>/dev/null | awk '{sub(/\/.*/,"",$4); print $4}')"})
  fi
  [[ -n "$ACTIVE_DEV" ]] && ACTIVE_SERVICE=$(dev_to_service "$ACTIVE_DEV")
  SYS_DNS=(${(u)${(f)"$(sys_dns_list)"}})
  if [[ "$GATEWAY" == *.*.*.* && -n "$(dig @"$GATEWAY" "$DOMAIN" +short +time=1 +tries=1 2>/dev/null)" ]]; then GW_DNS=1; fi
  if (( ${#GLOBAL6} )) && [[ -n "$(dig @2606:4700:4700::1111 "$DOMAIN" +tries=1 +time=2 +short 2>/dev/null)" ]]; then HAS_V6=1; fi
}

dns_mode_str() {
  local m
  if (( IS_MAC )); then
    m=$(networksetup -getdnsservers "$ACTIVE_SERVICE" 2>/dev/null)
    if [[ "$m" == *"aren't any"* || -z "$m" ]]; then print "automatic (DHCP/router)"; else print "manual: ${(j:, :)${(f)m}}"; fi
  else
    if nm_usable; then
      if [[ "$(nmcli -g ipv4.ignore-auto-dns connection show "$ACTIVE_SERVICE" 2>/dev/null)" == yes ]]; then
        print "manual (NetworkManager): $(nmcli -g ipv4.dns connection show "$ACTIVE_SERVICE" 2>/dev/null)"
      else print "automatic (NetworkManager/DHCP)"; fi
    elif need resolvectl && resolved_active; then print "systemd-resolved"
    else print "/etc/resolv.conf"; fi
  fi
}
nm_usable()       { need nmcli && [[ "$(nmcli -t -f RUNNING general 2>/dev/null)" == running ]] && [[ -n "$ACTIVE_SERVICE" ]] && nmcli connection show "$ACTIVE_SERVICE" >/dev/null 2>&1 }
resolved_active() { need systemctl && systemctl is-active --quiet systemd-resolved 2>/dev/null }

# =====================================================================
# apply / reset / flush
# =====================================================================
flush_dns_cache() {
  if (( IS_MAC )); then
    run_root dscacheutil -flushcache; run_root killall -HUP mDNSResponder
  else
    if   need resolvectl;      then run_root resolvectl flush-caches 2>/dev/null
    elif need systemd-resolve; then run_root systemd-resolve --flush-caches 2>/dev/null
    elif need nscd;            then run_root nscd -i hosts 2>/dev/null; fi
  fi
  return 0
}

save_backup() {
  local f="$HOME/.dns-bench-previous.txt"
  print -r -- "$(date '+%F %T') service=${ACTIVE_SERVICE} dev=${ACTIVE_DEV} mode=$(dns_mode_str) in_use=${SYS_DNS[*]}" >> "$f" 2>/dev/null
}

check_root_possible() {
  (( EUID == 0 )) && return 0
  need sudo || die "need root: run as root or install sudo"
  return 0
}

apply_dns() {   # apply_dns SERVER...   (v4 and v6 mixed)
  local -a v4 v6; local x
  for x in "$@"; do if [[ "$x" == *:* ]]; then v6+=($x); else v4+=($x); fi; done
  [[ -n "$ACTIVE_DEV" ]] || die "no active network interface found"
  check_root_possible
  save_backup
  if (( IS_MAC )); then
    [[ -n "$ACTIVE_SERVICE" ]] || die "could not map $ACTIVE_DEV to a network service"
    run_root networksetup -setdnsservers "$ACTIVE_SERVICE" "$@" || return 1
  elif nm_usable; then
    run_root nmcli connection modify "$ACTIVE_SERVICE" ipv4.dns "${(j: :)v4}" ipv4.ignore-auto-dns yes || return 1
    if (( ${#v6} )); then run_root nmcli connection modify "$ACTIVE_SERVICE" ipv6.dns "${(j: :)v6}" ipv6.ignore-auto-dns yes; fi
    run_root nmcli device reapply "$ACTIVE_DEV" >/dev/null 2>&1 || run_root nmcli connection up "$ACTIVE_SERVICE" >/dev/null
  elif need resolvectl && resolved_active; then
    run_root resolvectl dns "$ACTIVE_DEV" "$@" || return 1
    warn "set through systemd-resolved only: it may be lost on reconnect/reboot. NetworkManager or systemd-networkd config makes it permanent."
  else
    if [[ -L /etc/resolv.conf ]]; then warn "/etc/resolv.conf is managed by another tool (symlink), not touching it"; return 1; fi
    run_root cp -p /etc/resolv.conf /etc/resolv.conf.dns-bench.bak 2>/dev/null
    printf 'nameserver %s\n' "$@" | run_root tee /etc/resolv.conf >/dev/null || return 1
  fi
  flush_dns_cache
  return 0
}

reset_dns() {
  [[ -n "$ACTIVE_DEV" ]] || die "no active network interface found"
  check_root_possible
  if (( IS_MAC )); then
    [[ -n "$ACTIVE_SERVICE" ]] || die "could not map $ACTIVE_DEV to a network service"
    run_root networksetup -setdnsservers "$ACTIVE_SERVICE" Empty || return 1
  elif nm_usable; then
    run_root nmcli connection modify "$ACTIVE_SERVICE" ipv4.dns "" ipv4.ignore-auto-dns no ipv6.dns "" ipv6.ignore-auto-dns no || return 1
    run_root nmcli device reapply "$ACTIVE_DEV" >/dev/null 2>&1 || run_root nmcli connection up "$ACTIVE_SERVICE" >/dev/null
  elif need resolvectl && resolved_active; then
    run_root resolvectl revert "$ACTIVE_DEV" || return 1
  elif [[ -f /etc/resolv.conf.dns-bench.bak && ! -L /etc/resolv.conf ]]; then
    run_root cp -p /etc/resolv.conf.dns-bench.bak /etc/resolv.conf || return 1
  else
    warn "nothing to reset on this system"; return 1
  fi
  flush_dns_cache
  return 0
}

# =====================================================================
# resolver list
# =====================================================================
# "Name|Kind|Region|IPv4 primary|IPv4 secondary|IPv6 primary|IPv6 secondary"
# Kind: U unfiltered | F filters/blocks content | A blocks ads/trackers | C your current/local resolver (baseline only)
# Region: GL global anycast, NA, SA, EU, AS, OC, AF
typeset -A RNAME=(GL "Global anycast" NA "North America" SA "South America" EU "Europe" AS "Asia" OC "Oceania" AF "Africa" LAN "Local network")

build_resolvers() {
  RESOLVERS=(
    "Cloudflare|U|GL|1.1.1.1|1.0.0.1|2606:4700:4700::1111|2606:4700:4700::1001"
    "Cloudflare Malware|F|GL|1.1.1.2|1.0.0.2|2606:4700:4700::1112|2606:4700:4700::1002"
    "Cloudflare Family|F|GL|1.1.1.3|1.0.0.3|2606:4700:4700::1113|2606:4700:4700::1003"
    "Google Public DNS|U|GL|8.8.8.8|8.8.4.4|2001:4860:4860::8888|2001:4860:4860::8844"
    "Quad9 (Filtered)|F|GL|9.9.9.9|149.112.112.112|2620:fe::fe|2620:fe::9"
    "Quad9 (Unfiltered)|U|GL|9.9.9.10|149.112.112.10|2620:fe::10|2620:fe::fe:10"
    "Quad9 (ECS)|F|GL|9.9.9.11|149.112.112.11|2620:fe::11|2620:fe::fe:11"
    "OpenDNS Home|F|GL|208.67.222.222|208.67.220.220|2620:119:35::35|2620:119:53::53"
    "OpenDNS Family|F|GL|208.67.222.123|208.67.220.123|2620:119:35::123|2620:119:53::123"
    "AdGuard Default (ads)|A|GL|94.140.14.14|94.140.15.15|2a10:50c0::ad1:ff|2a10:50c0::ad2:ff"
    "AdGuard Family|F|GL|94.140.14.15|94.140.15.16|2a10:50c0::bad1:ff|2a10:50c0::bad2:ff"
    "AdGuard Unfiltered|U|GL|94.140.14.140|94.140.14.141|2a10:50c0::1:ff|2a10:50c0::2:ff"
    "Control D Unfiltered|U|GL|76.76.2.0|76.76.10.0|2606:1a40::|2606:1a40:1::"
    "Control D Malware|F|GL|76.76.2.1|76.76.10.1|2606:1a40::1|2606:1a40:1::1"
    "Control D Ads|A|GL|76.76.2.2|76.76.10.2|2606:1a40::2|2606:1a40:1::2"
    "NextDNS (Anycast)|U|GL|45.90.28.0|45.90.30.0|2a07:a8c0::|2a07:a8c1::"
    "Mullvad DNS|U|EU|194.242.2.2|none|2a07:e340::2|none"
    "Mullvad Adblock|A|EU|194.242.2.3|none|2a07:e340::3|none"
    "CleanBrowsing Security|F|GL|185.228.168.9|185.228.169.9|2a0d:2a00:1::2|2a0d:2a00:2::2"
    "CleanBrowsing Family|F|GL|185.228.168.168|185.228.169.168|2a0d:2a00:1::|2a0d:2a00:2::"
    "CleanBrowsing Adult Filter|F|GL|185.228.168.10|185.228.169.11|2a0d:2a00:1::1|2a0d:2a00:2::1"
    "DNS.SB|U|GL|185.222.222.222|45.11.45.11|2a09::|2a11::"
    "Comodo Secure DNS|F|NA|8.26.56.26|8.20.247.20|none|none"
    "Verisign Public DNS|U|GL|64.6.64.6|64.6.65.6|2620:74:1b::1:1|2620:74:1c::2:2"
    "Level3 / Lumen|U|NA|4.2.2.1|4.2.2.2|none|none"
    "Neustar UltraDNS|U|GL|156.154.70.1|156.154.71.1|2610:a1:1018::1|2610:a1:1019::1"
    "Hurricane Electric|U|GL|74.82.42.42|none|2001:470:20::2|none"
    "Alternate DNS (ads)|A|GL|76.76.19.19|76.223.122.150|2602:fcbc::ad|2602:fcbc:2::ad"
    "OpenNIC (anycast)|U|GL|185.121.177.177|169.239.202.202|none|none"
    "CIRA Shield Private|U|NA|149.112.121.10|149.112.122.10|2620:10A:80BB::10|2620:10A:80BC::10"
    "CIRA Shield Protected|F|NA|149.112.121.20|149.112.122.20|2620:10A:80BB::20|2620:10A:80BC::20"
    "DNS4EU (Unfiltered)|U|EU|86.54.11.100|86.54.11.200|2a13:1001::86:54:11:100|2a13:1001::86:54:11:200"
    "DNS0.eu|F|EU|193.110.81.0|185.253.5.0|2a0f:fc80::|2a0f:fc81::"
    "DNS0.eu Open|U|EU|193.110.81.254|185.253.5.254|2a0f:fc80::254|2a0f:fc81::254"
    "DNS.WATCH|U|EU|84.200.69.80|84.200.70.40|2001:1608:10:25::1c04:b12f|2001:1608:10:25::9249:d69b"
    "UncensoredDNS|U|EU|91.239.100.100|89.233.43.71|2001:67c:28a4::|2a01:3a0:53:53::"
    "Digitale Gesellschaft|U|EU|185.95.218.42|185.95.218.43|2a02:c205:3001:4558::1|2a02:c205:3001:4558::2"
    "SafeDNS|F|EU|195.46.39.39|195.46.39.40|none|none"
    "Yandex Basic|U|EU|77.88.8.8|77.88.8.1|2a02:6b8::feed:0ff|2a02:6b8:0:1::feed:0ff"
    "Yandex Safe|F|EU|77.88.8.88|77.88.8.2|2a02:6b8::feed:bad|2a02:6b8:0:1::feed:bad"
    "Yandex Family|F|EU|77.88.8.7|77.88.8.3|2a02:6b8::feed:a11|2a02:6b8:0:1::feed:a11"
    "Quad101 (TWNIC)|U|AS|101.101.101.101|101.102.103.104|2001:de4::101|2001:de4::102"
    "AliDNS|U|AS|223.5.5.5|223.6.6.6|2400:3200::1|2400:3200:baba::1"
    "DNSPod (Tencent)|U|AS|119.29.29.29|182.254.116.116|none|none"
    "Baidu DNS|U|AS|180.76.76.76|none|2400:da00::6666|none"
    "114DNS|U|AS|114.114.114.114|114.114.115.115|none|none"
    "CNNIC SDNS|U|AS|1.2.4.8|210.2.4.8|none|none"
    "KT (Korea Telecom)|U|AS|168.126.63.1|168.126.63.2|none|none"
    "LG U+ (Korea)|U|AS|164.124.101.2|203.248.252.2|none|none"
    "SingTel (Singapore)|U|AS|165.21.83.88|165.21.100.88|none|none"
    "dnsforge.de (ads)|A|EU|176.9.93.198|none|none|none"
  )
  local d
  if (( GW_DNS )); then RESOLVERS+=("Router / Gateway|C|LAN|$GATEWAY|none|none|none"); fi
  for d in $SYS_DNS; do
    if [[ "$d" == <->.<->.<->.<-> && "$d" != "$GATEWAY" ]]; then RESOLVERS+=("Current system DNS|C|LAN|$d|none|none|none"); break; fi
  done
  TOTAL=${#RESOLVERS}
}

resolver_of_ip() {   # prints "idx" of the resolver entry that has this IP (v4 or v6), else nothing
  local i e
  for (( i = 1; i <= ${#RESOLVERS}; i++ )); do
    e=${RESOLVERS[$i]}
    [[ "${e%%|C|*}" != "$e" ]] && continue
    [[ "|$e|" == *"|$1|"* ]] && { print $i; return }
  done
}

# =====================================================================
# benchmark engine
# =====================================================================
calc_score() {  # lower is better: cold lookups weigh double, packet loss is penalised
  local c=$1 k=$2 l=$3 base
  is_num "$c" || { print 99999.0; return }
  if is_num "$k"; then base=$(( (c + 2.0 * k) / 3 )); else base=$(( c * 3.0 )); fi
  printf "%.1f" $(( base + l * 3.0 ))
}

probe() {
  local idx=$1 entry=$2 name kind region a b c d
  local cm cmin cmax closs cold x1 x2 x3 x4 v4p v4pl v6m="N/A" v6p="N/A" dsec="-" nx="-" tcp="-" dot="-" doh="-" ads="-" pop="-" jit="-" score skey
  seed_probe_rng "$idx"   # before any random draw: forked workers share $RANDOM state
  IFS="|" read -r name kind region a b c d <<< "$entry"
  read -r cm cmin cmax closs <<< "$(dns_stats "$a" cached $SAMPLES)"
  if is_num "$cm"; then
    read -r cold x1 x2 x3 <<< "$(dns_stats "$a" cold 3 "$idx")"
    jit=$(( cmax - cmin ))
    nx=$(t_nx "$a" "$idx")
    if (( ! FAST )); then
      read -r v4p v4pl <<< "$(ping_stats "$a" 4)"
      if (( HAS_V6 )) && [[ "$c" != none ]]; then
        read -r v6m x1 x2 x3 <<< "$(dns_stats "$c" cached 3)"
        read -r v6p x4 <<< "$(ping_stats "$c" 6)"
      fi
      dsec=$(t_dnssec "$a"); tcp=$(t_tcp "$a")
      dot=$(t_port "$a" 853); doh=$(t_port "$a" 443)
      pop=$(t_pop "$a" "$name")
    else
      v4p="-"
    fi
    if (( ! FAST )) || [[ "$kind" == A ]]; then ads=$(t_ads "$a"); fi
  else
    cold="-"; v4p="-"
  fi
  score=$(calc_score "$cm" "$cold" "${closs:-100}")
  skey=$(printf "%09.1f" "$score")
  print -r -- "$skey|$idx|$name|$kind|$region|$cm|$jit|${closs:-100}|$cold|$score|$v4p|$v6m|$v6p|$dsec|$nx|$tcp|$dot|$doh|$ads|$pop" > "$TMP/res.$idx"
}

bench_collect() {   # bench_collect "U C"   (kinds to probe; empty = all)
  local kinds=$1 i k n=0 mon= bar=0
  local -a pids
  rm -f $TMP/res.*(N)
  PROBE_IDX=()
  for (( i = 1; i <= TOTAL; i++ )); do
    k=${${(s:|:)RESOLVERS[$i]}[2]}
    [[ -z "$kinds" || " $kinds " == *" $k "* ]] && PROBE_IDX+=($i)
  done
  pb_start ${#PROBE_IDX} "Probing resolvers"
  if (( PB_ON )); then
    bar=1
    pb_watch "$TMP/res." &
    mon=$!
  elif (( ! QUIET )); then
    print -n "  Probing ${#PROBE_IDX} resolvers"
  fi
  for i in $PROBE_IDX; do
    probe $i "${RESOLVERS[$i]}" &
    pids+=($!)
    if (( ++n % MAXJOBS == 0 )); then
      wait $pids; pids=()
      (( bar || QUIET )) || print -n "."
    fi
  done
  (( ${#pids} )) && wait $pids
  if (( bar )); then pb_stop $mon; else (( QUIET )) || print " done."; fi
}

typeset -A CM KIND V6M NXR LOSS SCORE ADS NAMEOF
load_results() {
  local line skey idx name kind region cm jit loss cold score v4p v6m v6p dsec nx tcp dot doh ads pop
  CM=(); KIND=(); V6M=(); NXR=(); LOSS=(); SCORE=(); ADS=(); NAMEOF=()
  SORTED=(${(f)"$(cat $TMP/res.*(N) 2>/dev/null | sort)"})
  for line in $SORTED; do
    IFS="|" read -r skey idx name kind region cm jit loss cold score v4p v6m v6p dsec nx tcp dot doh ads pop <<< "$line"
    CM[$idx]=$cm; KIND[$idx]=$kind; V6M[$idx]=$v6m; NXR[$idx]=$nx; LOSS[$idx]=$loss; SCORE[$idx]=$score; ADS[$idx]=$ads; NAMEOF[$idx]=$name
  done
}

pick_best() {   # pick_best KIND [needads]  -> PICK_IDX PICK_NAME PICK_CM PICK_SCORE
  PICK_IDX=; PICK_NAME=; PICK_CM=; PICK_SCORE=
  local line skey idx name kind rest cm loss
  for line in $SORTED; do
    idx=${${(s:|:)line}[2]}
    [[ "${KIND[$idx]}" == "$1" ]] || continue
    cm=${CM[$idx]}; loss=${LOSS[$idx]}
    is_num "$cm" || continue
    (( loss <= 20 )) || continue
    [[ "${NXR[$idx]}" == HIJACK ]] && continue
    [[ "$2" == needads && "${ADS[$idx]}" != yes ]] && continue
    PICK_IDX=$idx; PICK_NAME=${NAMEOF[$idx]}; PICK_CM=$cm; PICK_SCORE=${SCORE[$idx]}
    return 0
  done
  return 1
}

apply_entry() {   # apply_entry IDX  (adds IPv6 servers only when v6 works here)
  local sel_name sel_kind sel_region a b c d
  local -a servers
  IFS="|" read -r sel_name sel_kind sel_region a b c d <<< "${RESOLVERS[$1]}"
  servers=("$a"); [[ "$b" != none ]] && servers+=("$b")
  if (( HAS_V6 )) && [[ "$c" != none ]] && { [[ -z "${V6M[$1]}" ]] || is_num "${V6M[$1]}" || [[ "${V6M[$1]}" == "N/A" ]]; }; then
    servers+=("$c"); [[ "$d" != none ]] && servers+=("$d")
  fi
  apply_dns "${servers[@]}"
}

# =====================================================================
# printing: network info
# =====================================================================
print_info() {
  section "Network"
  kv "Host" "$(hostname) | $( (( IS_MAC )) && print "macOS $(sw_vers -productVersion 2>/dev/null)" || print "$(. /etc/os-release 2>/dev/null; print ${PRETTY_NAME:-Linux})" ) | $(uname -m)"
  kv "Active interface" "${ACTIVE_SERVICE:-Unknown} ($ACTIVE_DEV)"
  (( TUNNEL )) && kv "Default route" "${C_Y}via tunnel $DEF_DEV (VPN?)${C_0}; physical interface shown above"
  local ssid media mac mtu mask vpns proxy
  if (( IS_MAC )); then
    ssid=$(networksetup -getairportnetwork "$ACTIVE_DEV" 2>/dev/null | awk -F': ' '/Current/ {print $2}')
    media=$(ifconfig "$ACTIVE_DEV" 2>/dev/null | awk -F'media: ' '/media:/ {print $2; exit}')
    mac=$(ifconfig "$ACTIVE_DEV" 2>/dev/null | awk '/ether/ {print $2; exit}')
    mtu=$(ifconfig "$ACTIVE_DEV" 2>/dev/null | awk '/mtu/ {print $NF; exit}')
    mask=$(ipconfig getoption "$ACTIVE_DEV" subnet_mask 2>/dev/null)
    vpns=$(scutil --nc list 2>/dev/null | grep -c Connected)
    proxy=$(scutil --proxy 2>/dev/null | awk '/(HTTP|HTTPS|SOCKS|ProxyAutoConfig)Enable : 1/ {printf "%s ", $1}')
  else
    ssid=$(iwgetid -r 2>/dev/null); [[ -z "$ssid" ]] && need nmcli && ssid=$(nmcli -t -f active,ssid dev wifi 2>/dev/null | awk -F: '$1=="yes" {print $2; exit}')
    local sp=$(cat /sys/class/net/$ACTIVE_DEV/speed 2>/dev/null)
    is_num "$sp" && (( sp > 0 )) && media="${sp} Mb/s"
    mac=$(cat /sys/class/net/$ACTIVE_DEV/address 2>/dev/null)
    mtu=$(cat /sys/class/net/$ACTIVE_DEV/mtu 2>/dev/null)
    mask=$(ip -4 -o addr show dev "$ACTIVE_DEV" 2>/dev/null | awk '{sub(/^[^\/]*/,"",$4); print $4; exit}')
    vpns=$(ip -o link show up 2>/dev/null | awk -F': ' '{print $2}' | grep -cE '^(tun|wg|tailscale|ppp|zt|ipsec)')
    proxy=$(env | grep -iE '^(http|https|all|socks)_proxy=' | cut -d= -f1 | tr '\n' ' ')
  fi
  [[ -n "$ssid" ]] && kv "Wi-Fi network" "$ssid"
  [[ -n "$media" ]] && kv "Link" "$media"
  kv "MAC / MTU" "${mac:-?} / ${mtu:-?}"
  kv "Local IPv4" "${LOCAL4:-none} ${mask}"
  kv "Local IPv6" "${GLOBAL6[1]:-none} ${C_D}(${#GLOBAL6} global address(es))${C_0}"
  kv "Gateway" "${GATEWAY:-unknown}"
  if (( IS_MAC )); then
    local dhcp=$(ipconfig getoption "$ACTIVE_DEV" server_identifier 2>/dev/null)
    [[ -n "$dhcp" ]] && kv "DHCP server" "$dhcp"
  fi
  kv "System proxy" "${proxy:-none}"
  kv "VPN connected" "$( (( vpns > 0 )) && print "yes ($vpns)" || print no )"

  if need traceroute; then
    ( traceroute -n -q 1 -w 1 -m 6 1.1.1.1 > "$TMP/trace" 2>/dev/null ) &
    TRACE_PID=$!
  elif need tracepath; then
    ( tracepath -n -m 6 1.1.1.1 > "$TMP/trace" 2>/dev/null ) &
    TRACE_PID=$!
  else
    TRACE_PID=
  fi

  if [[ "$GATEWAY" == *.*.*.* ]]; then
    local gw_avg gw_loss
    read -r gw_avg gw_loss <<< "$(ping_stats "$GATEWAY" 4)"
    kv "Gateway latency" "${gw_avg} ms, loss ${gw_loss}%"
  fi

  local search
  if (( IS_MAC )); then search=$(scutil --dns 2>/dev/null | awk '/^resolver #1$/{f=1;next} /^resolver #/{f=0} f && /search domain\[/ {printf "%s ", $4}')
  else search=$(awk '/^(search|domain)/ {for(i=2;i<=NF;i++) printf "%s ", $i}' /etc/resolv.conf 2>/dev/null); fi
  kv "System DNS (in use)" "${(j:, :)SYS_DNS:-unknown}"
  kv "DNS source" "$(dns_mode_str)"
  if (( IS_LINUX )) && [[ "${SYS_DNS[1]}" == 127.0.0.* ]]; then note "(127.0.0.x is a local stub resolver; its upstreams come from systemd-resolved / dnsmasq)"; fi
  if (( IS_MAC )); then local dd=$(ipconfig getoption "$ACTIVE_DEV" domain_name_server 2>/dev/null); [[ -n "$dd" ]] && kv "DNS from DHCP" "$dd"; fi
  [[ -n "$search" ]] && kv "Search domains" "$search"
  kv "Router answers DNS" "$( (( GW_DNS )) && print yes || print no )"

  local PUB4= PUB6= T4 T6 CF_COLO CF_WARP
  if (( NO_EXT )); then
    note "Privacy mode: skipping external IP/geo lookups."
  else
    T4=$(curl -4 -s -m 4 https://1.1.1.1/cdn-cgi/trace 2>/dev/null)
    T6=$(curl -6 -g -s -m 4 'https://[2606:4700:4700::1111]/cdn-cgi/trace' 2>/dev/null)
    PUB4=$(print -r -- "$T4" | awk -F= '/^ip=/ {print $2}')
    PUB6=$(print -r -- "$T6" | awk -F= '/^ip=/ {print $2}')
    CF_COLO=$(print -r -- "$T4" | awk -F= '/^colo=/ {print $2}')
    CF_WARP=$(print -r -- "$T4" | awk -F= '/^warp=/ {print $2}')
    [[ -z "$PUB4" ]] && PUB4=$(dig -4 +short myip.opendns.com @resolver1.opendns.com +time=2 +tries=1 2>/dev/null | tail -1)
    kv "Public IPv4" "${PUB4:-unknown}"
    kv "Public IPv6" "${PUB6:-none (IPv4-only connection)}"
    curl -4 -s -m 5 https://ipwho.is/ -o "$TMP/geo.json" 2>/dev/null
    if [[ -n "$(jget "$TMP/geo.json" city 2>/dev/null)" ]]; then
      kv "Location" "$(jget "$TMP/geo.json" city), $(jget "$TMP/geo.json" region), $(jget "$TMP/geo.json" country) [$(jget "$TMP/geo.json" continent)]"
      kv "ISP / ASN" "$(jget "$TMP/geo.json" isp) (AS$(jget "$TMP/geo.json" asn))"
      kv "Time zone" "$(jget "$TMP/geo.json" id)"
    else
      curl -4 -s -m 5 https://ipinfo.io/json -o "$TMP/geo.json" 2>/dev/null
      if [[ -n "$(jget "$TMP/geo.json" city 2>/dev/null)" ]]; then
        kv "Location" "$(jget "$TMP/geo.json" city), $(jget "$TMP/geo.json" region), $(jget "$TMP/geo.json" country)"
        kv "ISP / ASN" "$(jget "$TMP/geo.json" org)"
        kv "Time zone" "$(jget "$TMP/geo.json" timezone)"
      else
        note "Geo lookup unavailable (ipwho.is / ipinfo.io unreachable)."
      fi
    fi
    [[ -n "$CF_COLO" ]] && kv "Nearest Cloudflare PoP" "$CF_COLO   ${C_D}(WARP: ${CF_WARP:-?})${C_0}"
  fi

  local egress deg
  egress=$(dig +short whoami.akamai.net +time=2 +tries=1 2>/dev/null | tail -1)
  if [[ -n "$egress" ]]; then
    if [[ -n "$PUB4" && "$egress" == "$PUB4" ]]; then deg="same as your public IP (resolver is on your own network)"
    else deg="differs from your public IP (upstream/ISP or public resolver)"; fi
    kv "System resolver egress IP" "$egress ${C_D}$deg${C_0}"
  fi

  if [[ -n "$(dig @192.0.2.53 example.com +short +time=2 +tries=1 2>/dev/null)" ]]; then
    kv "DNS interception" "${C_R}YES: a query to an unroutable IP got an answer (router/ISP is hijacking port 53)${C_0}"
  else
    kv "DNS interception" "${C_G}none detected${C_0}"
  fi
  if curl -s -m 4 http://captive.apple.com/ 2>/dev/null | grep -q Success; then kv "Captive portal" "${C_G}no${C_0}"; else kv "Captive portal" "${C_Y}possible / no internet over HTTP${C_0}"; fi

  if [[ -n "$TRACE_PID" ]]; then
    wait $TRACE_PID 2>/dev/null
    if [[ -s "$TMP/trace" ]]; then
      print "  ${C_D}Path to 1.1.1.1 (first hops):${C_0}"
      awk 'NR>1 {printf "    %s\n", $0}' "$TMP/trace"
    fi
  fi
  kv "IPv6 to resolvers" "$( (( HAS_V6 )) && print "working" || print "not available (IPv6 columns skipped)" )"
}

# =====================================================================
# printing: benchmark tables
# =====================================================================
typeset -A BEST_REG_IDX
print_tables() {
  local line skey idx name kind region cm jit loss cold score v4p v6m v6p dsec nx tcp dot doh ads pop rank=1 rc scol
  local nrows=${#SORTED} n25=$(( ${#SORTED} / 4 ))
  BEST_REG_IDX=()
  print
  print -n "${C_W}"
  cell "Rank" 5; cell "#" 4; cell "Provider" 27; cell "Rgn" 4; cell "Kind" 5
  cell "Cached" 9; cell "Jitter" 8; cell "Loss" 6; cell "Cold" 9; cell "Score" 7
  cell "v4 ping" 9; cell "v6 DNS" 9; cell "v6 ping" 9
  print "${C_0}"
  print "  ${C_D}-------------------------------------------------------------------------------------------------------------${C_0}"
  for line in $SORTED; do
    IFS="|" read -r skey idx name kind region cm jit loss cold score v4p v6m v6p dsec nx tcp dot doh ads pop <<< "$line"
    rc=""; (( rank == 1 )) && rc=$C_B
    cell "$rank" 5 "$rc"; cell "$idx" 4; cell "$name" 27 "$rc"; cell "$region" 4; cell "$kind" 5
    ms_cell "$cm" 9; if is_num "$jit"; then cell "${jit} ms" 8 "$C_D"; else cell "-" 8 "$C_D"; fi
    if is_num "$loss" && (( loss > 0 )); then cell "${loss}%" 6 "$C_R"; else cell "${loss}%" 6 "$C_D"; fi
    ms_cell "$cold" 9
    scol=$C_R
    if (( rank == 1 )); then scol="${C_B}${C_G}"
    elif (( rank <= n25 )); then scol=$C_G
    elif (( rank <= nrows - n25 )); then scol=$C_Y; fi
    if is_num "$score" && (( score < 99999 )); then cell "$score" 7 "$scol"; else cell "-" 7 "$C_D"; fi
    ms_cell "$v4p" 9; ms_cell "$v6m" 9; ms_cell "$v6p" 9
    print
    if [[ "$kind" == U && -z "${BEST_REG_IDX[$region]}" ]] && is_num "$cm" && (( loss <= 20 )); then BEST_REG_IDX[$region]=$idx; fi
    (( rank++ ))
  done
  print "  ${C_D}Kind: U unfiltered | F filters/blocks content | A blocks ads | C your current/local resolver (baseline, never auto-selected)${C_0}"

  (( FAST )) && return
  section "Features & security"
  print -n "${C_W}"
  cell "#" 4; cell "Provider" 27; cell "DNSSEC" 8; cell "NXDOMAIN" 10; cell "TCP/53" 8; cell "DoT:853" 9; cell "443 open" 9; cell "Blocks ads" 11; cell "PoP / node" 24
  print "${C_0}"
  print "  ${C_D}-------------------------------------------------------------------------------------------------------------${C_0}"
  for line in $SORTED; do
    IFS="|" read -r skey idx name kind region cm jit loss cold score v4p v6m v6p dsec nx tcp dot doh ads pop <<< "$line"
    cell "$idx" 4; cell "$name" 27
    yn_cell "$dsec" 8 yes; yn_cell "$nx" 10 ok; yn_cell "$tcp" 8 yes; yn_cell "$dot" 9 yes; yn_cell "$doh" 9 yes
    cell "$ads" 11 "$C_D"; cell "$pop" 24 "$C_D"
    print
  done
  print "  ${C_D}DNSSEC: validates signatures | NXDOMAIN: HIJACK = rewrites non-existent names | DoT/443: port reachable from your network${C_0}"
  print "  ${C_D}Blocks ads: 2 of 3 known ad domains refused/null-routed | PoP: anycast node that answered you (when exposed)${C_0}"

  section "Best unfiltered resolver per region"
  local r ri rn rk rr ra rb rc2 rd
  for r in GL NA SA EU AS OC AF; do
    ri=${BEST_REG_IDX[$r]}
    [[ -n "$ri" ]] || continue
    IFS="|" read -r rn rk rr ra rb rc2 rd <<< "${RESOLVERS[$ri]}"
    printf "  %-16s %-26s %s ms\n" "${RNAME[$r]}" "$rn" "${CM[$ri]}"
  done
}

# =====================================================================
# continent latency + popular services
# =====================================================================
geo_test() {
  local -a GEO
  GEO=(
    "North America|N. Virginia|us-east-1" "North America|Oregon|us-west-2" "North America|Montreal|ca-central-1"
    "South America|Sao Paulo|sa-east-1"
    "Europe|Ireland|eu-west-1" "Europe|Frankfurt|eu-central-1" "Europe|Stockholm|eu-north-1"
    "Middle East|Bahrain|me-south-1" "Middle East|UAE|me-central-1"
    "Africa|Cape Town|af-south-1"
    "Asia|Mumbai|ap-south-1" "Asia|Hyderabad|ap-south-2" "Asia|Singapore|ap-southeast-1" "Asia|Hong Kong|ap-east-1" "Asia|Tokyo|ap-northeast-1"
    "Oceania|Sydney|ap-southeast-2"
  )
  geo_probe() {
    local i=$1 region=$2 k r ms
    local -a t
    for k in 1 2 3; do
      r=$(curl -4 -s -o /dev/null -m 4 --connect-timeout 3 -w '%{time_namelookup} %{time_connect}' "https://ec2.${region}.amazonaws.com/" 2>/dev/null)
      ms=$(print -r -- "$r" | awk '$2 > 0 {printf "%d", ($2-$1)*1000+0.5}')
      [[ "$ms" == <-> ]] && t+=($ms)
    done
    if (( ${#t} )); then t=(${(on)t}); print "${t[$(( (${#t} + 1) / 2 ))]}" > "$TMP/geo.$i"; else print "Timeout" > "$TMP/geo.$i"; fi
  }
  section "Latency to each continent (TCP connect, median of 3)"
  local i gc gcity greg ms nb lastc="" geo_best=99999 geo_best_label="" mon= bar=0
  local -a pids
  pb_start ${#GEO} "Testing continents"
  (( PB_ON )) && { bar=1; pb_watch "$TMP/geo." & mon=$! }
  for (( i = 1; i <= ${#GEO}; i++ )); do
    IFS="|" read -r gc gcity greg <<< "${GEO[$i]}"
    geo_probe $i $greg &
    pids+=($!)
  done
  wait $pids
  (( bar )) && pb_stop $mon
  for (( i = 1; i <= ${#GEO}; i++ )); do
    IFS="|" read -r gc gcity greg <<< "${GEO[$i]}"
    ms=$(<"$TMP/geo.$i")
    if [[ "$gc" != "$lastc" ]]; then [[ -n "$lastc" ]] && print; cell "  $gc" 18 "$C_B"; lastc=$gc; else cell "" 18; fi
    cell "$gcity" 14; cell "$greg" 16 "$C_D"; ms_cell "$ms" 9
    if is_num "$ms"; then
      nb=$(( ms / 12 )); (( nb > 30 )) && nb=30
      print -n " ${(l:$nb::#:)}"
      (( ms < geo_best )) && { geo_best=$ms; geo_best_label="$gcity ($gc)" }
    fi
    print
  done
  [[ -n "$geo_best_label" ]] && print "\n  ${C_D}Closest cloud region:${C_0} $geo_best_label at ${geo_best} ms. Region latency is physical distance, it doesn't depend on your DNS choice."
}

BEST_SVC_IDX=""; BEST_SVC_NAME=""; BEST_SVC_AVG=""
svc_test() {
  local -a SERVICES SVC_IDX
  SERVICES=(
    "Google|www.google.com" "YouTube|www.youtube.com" "Google Meet|meet.google.com"
    "Facebook|www.facebook.com" "Instagram|www.instagram.com" "WhatsApp Web|web.whatsapp.com"
    "X / Twitter|x.com" "LinkedIn|www.linkedin.com" "Reddit|www.reddit.com"
    "Netflix|www.netflix.com" "Prime Video|www.primevideo.com" "Spotify|open.spotify.com"
    "Hotstar|www.hotstar.com" "Apple|www.apple.com" "Microsoft|www.microsoft.com"
    "Teams|teams.microsoft.com" "Zoom|zoom.us" "Amazon|www.amazon.com" "Flipkart|www.flipkart.com"
    "GitHub|github.com" "npm registry|registry.npmjs.org" "PyPI|pypi.org" "Docker Hub|registry-1.docker.io"
    "OpenAI API|api.openai.com" "Anthropic API|api.anthropic.com"
    "cdnjs|cdnjs.cloudflare.com" "jsDelivr|cdn.jsdelivr.net" "AWS S3|s3.amazonaws.com"
    "Steam|store.steampowered.com" "Wikipedia|www.wikipedia.org"
  )
  local h
  if [[ -n "$EXTRA_SVC" ]]; then
    for h in ${(s:,:)EXTRA_SVC}; do [[ "$h" =~ '^[A-Za-z0-9.-]+$' ]] && SERVICES+=("$h|$h"); done
  fi

  local line idx name kind region cm rest cnt=0 CUR_IDX=""
  SVC_IDX=()
  for line in $SORTED; do
    IFS="|" read -r skey idx name kind region cm rest <<< "$line"
    [[ "$name" == "Current system DNS" ]] && is_num "$cm" && CUR_IDX=$idx
    if [[ "$kind" == U ]] && is_num "$cm" && (( cnt < TOPK )) && [[ "${NXR[$idx]}" != HIJACK ]]; then SVC_IDX+=($idx); (( cnt++ )); fi
  done
  [[ -n "$CUR_IDX" ]] && SVC_IDX+=($CUR_IDX)
  (( ${#SVC_IDX} )) || { warn "no resolver answered; skipping service test"; return }

  svc_probe() {   # svc_probe S RI IP HOST
    local s=$1 ri=$2 ip=$3 host=$4 out lk ans rtt
    out=$(dig @"$ip" "$host" A +tries=1 +time=2 +stats 2>/dev/null)
    lk=$(print -r -- "$out" | awk '/Query time:/ {print $4; exit}')
    ans=$(print -r -- "$out" | awk '$0 !~ /^;/ && $3=="IN" && $4=="A" {print $5; exit}')
    if [[ -z "$ans" ]]; then rtt="NoAnswer"
    elif [[ "$ans" == (0.0.0.0|127.*|146.112.61.*) ]]; then rtt="Blocked"
    else
      rtt=$(curl -4 -s -o /dev/null -m 4 --connect-timeout 3 --resolve "$host:443:$ans" -w '%{time_connect}' "https://$host/" 2>/dev/null | awk '$1 > 0 {printf "%d", $1*1000+0.5}')
      [[ "$rtt" == <-> ]] || rtt="Timeout"
    fi
    print -r -- "${lk:--} ${ans:--} $rtt" > "$TMP/svc.$s.$ri"
  }

  section "Popular services: edge RTT returned by each resolver (${#SERVICES} services x ${#SVC_IDX} resolvers)"
  print "  Each cell = TCP connect time to the IP that resolver handed back. Lower = closer CDN edge. ${C_G}green${C_0} = best in row."
  local n=0 s ri sname shost rn rk rr ra rb rc rd mon= bar=0
  local -a pids
  pb_start $(( ${#SERVICES} * ${#SVC_IDX} )) "Testing popular services"
  (( PB_ON )) && { bar=1; pb_watch "$TMP/svc." & mon=$! }
  (( bar )) || print -n "  Running"
  for (( s = 1; s <= ${#SERVICES}; s++ )); do
    IFS="|" read -r sname shost <<< "${SERVICES[$s]}"
    for ri in $SVC_IDX; do
      IFS="|" read -r rn rk rr ra rb rc rd <<< "${RESOLVERS[$ri]}"
      svc_probe $s $ri $ra $shost &
      pids+=($!)
      if (( ++n % MAXJOBS == 0 )); then
        wait $pids; pids=()
        (( bar )) || print -n "."
      fi
    done
  done
  (( ${#pids} )) && wait $pids
  if (( bar )); then pb_stop $mon; print; else print " done.\n"; fi

  typeset -A SUMRTT CNTRTT SUMLK CNTLK WINS BAD
  local lk ans rtt rowmin j v col avg lkavg bestavg=99999
  local -a ROWV
  print -n "${C_B}"; cell "  Service" 20
  for ri in $SVC_IDX; do IFS="|" read -r rn rk rr ra rb rc rd <<< "${RESOLVERS[$ri]}"; cell "${rn[1,11]}" 12; done
  print "${C_0}"
  for (( s = 1; s <= ${#SERVICES}; s++ )); do
    IFS="|" read -r sname shost <<< "${SERVICES[$s]}"
    ROWV=(); rowmin=99999
    for ri in $SVC_IDX; do
      read -r lk ans rtt < "$TMP/svc.$s.$ri"
      ROWV+=("$rtt")
      if is_num "$lk"; then (( SUMLK[$ri] += lk )); (( CNTLK[$ri] += 1 )); fi
      if is_num "$rtt"; then
        (( SUMRTT[$ri] += rtt )); (( CNTRTT[$ri] += 1 ))
        (( rtt < rowmin )) && rowmin=$rtt
      else
        (( BAD[$ri] += 1 ))
      fi
    done
    cell "  $sname" 20
    j=1
    for ri in $SVC_IDX; do
      v=${ROWV[$j]}
      if is_num "$v"; then
        if (( v <= rowmin + 3 )); then col=$C_G; (( WINS[$ri] += 1 ))
        elif (( v >= rowmin * 2 + 15 )); then col=$C_R
        else col=""; fi
        cell "$v ms" 12 "$col"
      else cell "$v" 12 "$C_R"; fi
      (( j++ ))
    done
    print
  done

  print
  print -n "${C_B}"; cell "  Resolver summary" 28; cell "Avg edge RTT" 14; cell "Avg lookup" 12; cell "Best-in-row" 13; cell "Failed" 8; print "${C_0}"
  for ri in $SVC_IDX; do
    IFS="|" read -r rn rk rr ra rb rc rd <<< "${RESOLVERS[$ri]}"
    if (( ${CNTRTT[$ri]:-0} > 0 )); then avg=$(( ${SUMRTT[$ri]} / ${CNTRTT[$ri]} )); else avg=99999; fi
    if (( ${CNTLK[$ri]:-0} > 0 )); then lkavg=$(( ${SUMLK[$ri]} / ${CNTLK[$ri]} )); else lkavg=0; fi
    cell "  $rn" 28; ms_cell "$(printf '%.0f' $avg)" 14; ms_cell "$(printf '%.0f' $lkavg)" 12
    cell "${WINS[$ri]:-0}/${#SERVICES}" 13; cell "${BAD[$ri]:-0}" 8; print
    if [[ "$rk" == U ]] && (( avg < bestavg )) && (( ${BAD[$ri]:-0} * 100 / ${#SERVICES} <= 20 )); then bestavg=$avg; BEST_SVC_IDX=$ri; BEST_SVC_NAME=$rn; BEST_SVC_AVG=$avg; fi
  done
  print "  ${C_D}NoAnswer/Blocked/Timeout count as failures. Edge RTT also reflects Wi-Fi/ISP noise, rerun a couple of times.${C_0}"
}

# =====================================================================
# commands
# =====================================================================
csv_default_path() {   # timestamped file next to the script (falls back to $HOME, then $PWD)
  local dir=${DNSBENCH_CSV_DIR:-$SELF_DIR}
  [[ -d "$dir" && -w "$dir" ]] || dir=$HOME
  [[ -d "$dir" && -w "$dir" ]] || dir=$PWD
  print -r -- "$dir/dns-bench-$HOST-$(date '+%Y%m%d-%H%M%S').csv"
}

write_csv() {   # write_csv FILE
  local f=$1
  { print "sortkey,idx,name,kind,region,cached_ms,jitter_ms,loss_pct,cold_ms,score,v4_ping,v6_dns,v6_ping,dnssec,nxdomain,tcp53,dot853,port443,blocks_ads,pop"
    print -rl -- ${SORTED//|/,}; } > "$f" || return 1
}

export_csv() {   # export_csv [FILE]  -> writes CSV, prints where it went
  local f=$1
  [[ -n "$f" ]] || (( CSV_AUTO && ! QUIET )) || return 0
  [[ -n "$f" ]] || f=$(csv_default_path)
  if write_csv "$f"; then
    print "  Results saved to ${C_B}$f${C_0}"
  else
    warn "could not write CSV to $f"
  fi
}

print_summary() {
  section "Summary"
  kv "Fastest DNS (unfiltered)" "#$PICK_IDX $PICK_NAME: cached ${PICK_CM} ms, score ${PICK_SCORE}"
  [[ -n "$BEST_SVC_IDX" ]] && kv "Best for popular services" "#$BEST_SVC_IDX $BEST_SVC_NAME (avg edge RTT $(printf '%.0f' $BEST_SVC_AVG) ms)"
  local line skey idx name kind region cm jit loss cold score rest diff
  for line in $SORTED; do
    IFS="|" read -r skey idx name kind region cm jit loss cold score rest <<< "$line"
    if [[ "$name" == "Current system DNS" ]]; then
      kv "Your current DNS" "$name: cached ${cm} ms, cold ${cold} ms, score ${score}"
      if is_num "$score" && is_num "$PICK_SCORE"; then
        diff=$(printf '%.0f' $(( score - PICK_SCORE )))
        if (( diff > 5 )); then kv "" "${C_Y}the fastest resolver scores $diff points better${C_0}"; else kv "" "${C_G}already near the top${C_0}"; fi
      fi
      break
    fi
  done
  export_csv "$CSV_OUT"
}

apply_menu() {
  (( NO_APPLY )) && { print "\nReport only (-N). No changes made."; return 0 }
  if [[ -z "$ACTIVE_DEV" ]]; then print "\nNo active interface, so I won't change DNS."; return 1; fi
  local CHOICE YN
  if (( ASSUME_YES )); then CHOICE=best
  else
    print "\n${C_C}----------------------------------------------------------------------------------------------${C_0}"
    print "  [Enter]/best -> apply fastest unfiltered resolver ($PICK_NAME)"
    [[ -n "$BEST_SVC_IDX" ]] && print "  svc          -> apply best for popular services ($BEST_SVC_NAME)"
    print "  [1-$TOTAL]       -> apply a specific resolver by its # in the tables"
    print "  reset        -> revert to automatic DNS (DHCP / router)"
    print "  q            -> quit without changes"
    print -n "\nYour choice: "
    read -r CHOICE
  fi
  case "$CHOICE" in
    q|Q) print "No changes made."; return 0 ;;
    reset) print "Resetting DNS for '$ACTIVE_SERVICE' to automatic..."
           reset_dns && print "Done. DNS is back to the DHCP/router default and the cache is flushed." || print "Reset failed."
           return 0 ;;
    ""|best) CHOICE=$PICK_IDX ;;
    svc) [[ -n "$BEST_SVC_IDX" ]] && CHOICE=$BEST_SVC_IDX || { print "No service test was run."; return 1 } ;;
  esac
  if ! [[ "$CHOICE" == <-> ]] || (( CHOICE < 1 || CHOICE > TOTAL )); then print "Invalid selection. No changes made."; return 1; fi
  local sel_name sel_kind sel_region a b c d
  IFS="|" read -r sel_name sel_kind sel_region a b c d <<< "${RESOLVERS[$CHOICE]}"
  [[ "$sel_kind" == C ]] && { print "That's your local/current DNS; nothing to apply."; return 0 }
  [[ "$sel_kind" == F ]] && print "Note: $sel_name filters/blocks some domains."
  [[ "$sel_kind" == A ]] && print "Note: $sel_name blocks ads/trackers at the DNS level."
  [[ "${NXR[$CHOICE]}" == HIJACK ]] && print "${C_R}Warning: $sel_name rewrites non-existent domains (NXDOMAIN hijacking).${C_0}"
  if ! is_num "${CM[$CHOICE]}" && ! (( ASSUME_YES )); then
    print -n "$sel_name did not answer IPv4 queries in the test. Apply anyway? [y/N] "
    read -r YN; [[ "$YN" == [yY] ]] || { print "No changes made."; return 0 }
  fi
  print "\nApplying $sel_name to '${ACTIVE_SERVICE:-$ACTIVE_DEV}'..."
  if apply_entry $CHOICE; then
    print "Success. Servers now in use: ${(j:, :)$(sys_dns_list)}"
    print "(Previous setting logged to ~/.dns-bench-previous.txt. Run 'dns-bench reset' to go back to automatic.)"
  else
    print "Failed to apply DNS."; return 1
  fi
}

cmd_list() {
  build_resolvers
  local i name kind region a b c d
  printf "%-4s %-28s %-4s %-4s %-18s %s\n" "#" "Name" "Kind" "Rgn" "IPv4" "IPv6"
  for (( i = 1; i <= ${#RESOLVERS}; i++ )); do
    IFS="|" read -r name kind region a b c d <<< "${RESOLVERS[$i]}"
    printf "%-4s %-28s %-4s %-4s %-18s %s\n" "$i" "$name" "$kind" "$region" "$a" "$c"
  done
}

cmd_info() {
  detect_net
  [[ -n "$ACTIVE_DEV" ]] || die "no default route: you appear to be offline"
  print "${C_B}dns-bench $VERSION${C_0}  $(date '+%Y-%m-%d %H:%M:%S %Z')"
  print_info
}

cmd_run() {
  detect_net
  [[ -n "$ACTIVE_DEV" ]] || die "no default route: you appear to be offline"
  print "${C_B}dns-bench $VERSION${C_0}  $(date '+%Y-%m-%d %H:%M:%S %Z')  |  target: $DOMAIN  |  samples: $SAMPLES"
  print_info
  build_resolvers
  section "DNS benchmark: $TOTAL resolvers"
  print "  Cached = median of $SAMPLES queries for $DOMAIN | Cold = median of 3 random uncached names | Score = (cached + 2*cold)/3 + 3*loss%"
  note "Probing up to $MAXJOBS resolvers at once"
  bench_collect ""
  load_results
  print_tables
  pick_best U || { print "\nNo unfiltered resolver responded. Check your internet connection."; exit 1 }
  (( SKIP_GEO )) || geo_test
  (( SKIP_SVC )) || svc_test
  print_summary
  apply_menu
}

cmd_best() { SKIP_SVC=1; SKIP_GEO=1; FAST=1; QUIET=0; cmd_run }

cmd_adblock() {
  detect_net
  [[ -n "$ACTIVE_DEV" ]] || die "no default route: you appear to be offline"
  if [[ "$1" == off ]]; then
    print "Turning ad-blocking DNS off (back to automatic DNS)..."
    reset_dns && print "Done." || die "reset failed"
    return
  fi
  FAST=1; SAMPLES=3
  build_resolvers
  print "Testing ad-blocking resolvers..."
  bench_collect "A"
  load_results
  print
  cell "  Resolver" 28; cell "Cached" 10; cell "Cold" 10; cell "Blocks ads" 12; print
  local line idx
  for line in $SORTED; do
    idx=${${(s:|:)line}[2]}
    cell "  ${NAMEOF[$idx]}" 28; ms_cell "${CM[$idx]}" 10; ms_cell "$(print -r -- $line | cut -d'|' -f9)" 10; yn_cell "${ADS[$idx]}" 12 yes; print
  done
  if ! pick_best A needads; then die "no ad-blocking resolver answered and verified"; fi
  print "\n  Fastest that blocks: ${C_B}$PICK_NAME${C_0} (cached ${PICK_CM} ms)"
  export_csv "$CSV_OUT"
  if (( NO_APPLY )); then print "  Report only (-N)."; return; fi
  if (( ! ASSUME_YES )); then
    print -n "  Apply it? [Y/n] "; local YN; read -r YN
    [[ "$YN" == [nN] ]] && { print "No changes made."; return }
  fi
  if apply_entry $PICK_IDX; then
    print "  Ad-blocking DNS active: ${(j:, :)$(sys_dns_list)}"
    note "DNS blocking covers third-party ad/tracker domains. It can't remove ads served from the same domain as the content (YouTube, most in-app ads)."
    note "Undo with: dns-bench adblock off"
  else die "failed to apply DNS"; fi
}

cmd_set() {
  local q=$1 i name
  [[ -n "$q" ]] || die "usage: dns-bench set NAME|#   (see: dns-bench list)"
  detect_net
  [[ -n "$ACTIVE_DEV" ]] || die "no default route: you appear to be offline"
  build_resolvers
  local match=
  if [[ "$q" == <-> ]] && (( q >= 1 && q <= TOTAL )); then match=$q
  else
    for (( i = 1; i <= TOTAL; i++ )); do
      name=${${(s:|:)RESOLVERS[$i]}[1]}
      [[ "${(L)name}" == *"${(L)q}"* ]] && { match=$i; break }
    done
  fi
  [[ -n "$match" ]] || die "no resolver matches '$q' (see: dns-bench list)"
  name=${${(s:|:)RESOLVERS[$match]}[1]}
  print "Applying $name to '${ACTIVE_SERVICE:-$ACTIVE_DEV}'..."
  apply_entry $match && print "Done. Servers now in use: ${(j:, :)$(sys_dns_list)}" || die "failed to apply DNS"
}

cmd_reset() {
  detect_net
  [[ -n "$ACTIVE_DEV" ]] || die "no default route: you appear to be offline"
  print "Resetting DNS for '${ACTIVE_SERVICE:-$ACTIVE_DEV}' to automatic..."
  reset_dns && print "Done. DNS is back to the DHCP/router default and the cache is flushed." || die "reset failed"
}

installed_path() {
  local p
  p=$(command -v dns-bench 2>/dev/null)
  [[ -n "$p" && -x "$p" ]] && { print -r -- "$p"; return }
  for p in /usr/local/bin/dns-bench "$HOME/.local/bin/dns-bench"; do [[ -x "$p" ]] && { print -r -- "$p"; return }; done
}

cmd_install() {
  local dir target
  if (( $#o_sys )) || (( EUID == 0 )) || [[ -w /usr/local/bin ]]; then dir=/usr/local/bin; else dir=$HOME/.local/bin; fi
  target=$dir/dns-bench
  if [[ "${target:A}" == "$SELF" ]]; then print "Already installed at $target"
  else
    if [[ $dir == $HOME/* ]]; then mkdir -p "$dir" && cp "$SELF" "$target" && chmod 755 "$target" || die "install failed"
    else
      if [[ -w $dir ]]; then cp "$SELF" "$target" && chmod 755 "$target" || die "install failed"
      else run_root mkdir -p "$dir" && run_root install -m 755 "$SELF" "$target" || die "install failed"; fi
    fi
    print "Installed: $target"
  fi
  if [[ ":$PATH:" != *":$dir:"* ]]; then
    print "$dir is not in your PATH. add this to your shell rc (~/.zshrc or ~/.bashrc):"
    print "  export PATH=\"$dir:\$PATH\""
  else
    print "Run it with: dns-bench"
  fi
}

cron_expr() {   # cron_expr WHEN AT -> 5-field expression
  local when=$1 at=${2:-04:00} hh mm
  hh=${at%%:*}; mm=${at##*:}; hh=$((10#$hh)); mm=$((10#$mm))
  case "$when" in
    hourly) print "7 * * * *" ;;
    6h)     print "7 */6 * * *" ;;
    daily)  print "$mm $hh * * *" ;;
    weekly) print "$mm $hh * * 0" ;;
    <1-30>d) print "$mm $hh */${when%d} * *" ;;
    *)      if [[ "$when" == *\ *\ *\ *\ * ]]; then print -r -- "$when"; else return 1; fi ;;
  esac
}

cmd_cron() {
  local when=$1 prof=${o_prof[-1]:-best} at=${o_at[-1]:-04:00} inst expr
  [[ -n "$when" ]] || die "usage: dns-bench cron hourly|6h|daily|weekly|2d|off   (or a 5-field cron expression)"
  [[ "$prof" == (best|adblock) ]] || die "--profile must be best or adblock"
  [[ "$at" =~ '^[0-9]{1,2}:[0-9]{2}$' ]] || die "--at must be HH:MM"
  if [[ "$when" == off ]]; then cron_remove; return; fi
  check_root_possible
  inst=$(installed_path)
  if [[ -z "$inst" ]]; then
    print "Not installed yet, installing first..."
    cmd_install
    inst=$(installed_path)
    [[ -n "$inst" ]] || die "install failed; can't schedule"
  fi
  expr=$(cron_expr "$when" "$at") || die "unknown schedule '$when'"
  local line="$inst auto --profile $prof"
  if (( IS_MAC )); then
    local sched
    case "$when" in
      hourly) sched="<key>StartInterval</key><integer>3600</integer>" ;;
      6h)     sched="<key>StartInterval</key><integer>21600</integer>" ;;
      daily)  sched="<key>StartCalendarInterval</key><dict><key>Hour</key><integer>$((10#${at%%:*}))</integer><key>Minute</key><integer>$((10#${at##*:}))</integer></dict>" ;;
      weekly) sched="<key>StartCalendarInterval</key><dict><key>Weekday</key><integer>0</integer><key>Hour</key><integer>$((10#${at%%:*}))</integer><key>Minute</key><integer>$((10#${at##*:}))</integer></dict>" ;;
      <1-30>d) sched="<key>StartInterval</key><integer>$(( ${when%d} * 86400 ))</integer>" ;;
      *) die "on macOS use hourly, 6h, daily, weekly or Nd (e.g. 2d)" ;;
    esac
    cat > "$TMP/com.dns-bench.auto.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.dns-bench.auto</string>
<key>ProgramArguments</key><array><string>$inst</string><string>auto</string><string>--profile</string><string>$prof</string></array>
$sched
<key>StandardOutPath</key><string>/var/log/dns-bench.log</string>
<key>StandardErrorPath</key><string>/var/log/dns-bench.log</string>
</dict></plist>
EOF
    run_root launchctl bootout system/com.dns-bench.auto >/dev/null 2>&1
    run_root install -m 644 -o root -g wheel "$TMP/com.dns-bench.auto.plist" /Library/LaunchDaemons/com.dns-bench.auto.plist || die "could not write launchd plist"
    run_root launchctl bootstrap system /Library/LaunchDaemons/com.dns-bench.auto.plist || die "launchctl bootstrap failed"
    print "Scheduled (launchd, runs as root): $when${at:+ at $at} | profile: $prof | log: /var/log/dns-bench.log"
  elif [[ -d /etc/cron.d ]] && need cron || need crond; then
    if [[ -d /etc/cron.d ]]; then
      printf '# managed by dns-bench\nPATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\n%s root %s >> /var/log/dns-bench.log 2>&1\n' "$expr" "$line" | run_root tee /etc/cron.d/dns-bench >/dev/null || die "could not write /etc/cron.d/dns-bench"
      run_root chmod 644 /etc/cron.d/dns-bench
      print "Scheduled (/etc/cron.d/dns-bench): $expr | profile: $prof | log: /var/log/dns-bench.log"
    else
      ( run_root crontab -l 2>/dev/null | grep -v 'dns-bench auto'; print -r -- "$expr $line >> /var/log/dns-bench.log 2>&1" ) | run_root crontab - || die "crontab install failed"
      print "Scheduled (root crontab): $expr | profile: $prof | log: /var/log/dns-bench.log"
    fi
  elif need systemctl; then
    local cal
    case "$when" in
      hourly) cal="hourly" ;;
      6h)     cal="*-*-* 00/6:07:00" ;;
      daily)  cal="*-*-* $at:00" ;;
      weekly) cal="Sun *-*-* $at:00" ;;
      <1-30>d) cal="*-*-1/${when%d} $at:00" ;;
      *) die "no cron found; with the systemd fallback use hourly, 6h, daily, weekly or Nd" ;;
    esac
    printf '[Unit]\nDescription=dns-bench auto\n\n[Service]\nType=oneshot\nExecStart=%s\nStandardOutput=append:/var/log/dns-bench.log\nStandardError=append:/var/log/dns-bench.log\n' "$line" | run_root tee /etc/systemd/system/dns-bench.service >/dev/null
    printf '[Unit]\nDescription=dns-bench schedule\n\n[Timer]\nOnCalendar=%s\nPersistent=true\n\n[Install]\nWantedBy=timers.target\n' "$cal" | run_root tee /etc/systemd/system/dns-bench.timer >/dev/null
    run_root systemctl daemon-reload && run_root systemctl enable --now dns-bench.timer || die "systemd timer setup failed"
    print "Scheduled (systemd timer): $cal | profile: $prof | log: /var/log/dns-bench.log"
  else
    die "no cron, crond or systemd found"
  fi
  note "auto only switches DNS when the new resolver scores at least ${o_gain[-1]:-20}% better than what you use now."
}

cron_remove() {
  local removed=0
  if (( IS_MAC )); then
    if [[ -f /Library/LaunchDaemons/com.dns-bench.auto.plist ]]; then
      run_root launchctl bootout system/com.dns-bench.auto >/dev/null 2>&1
      run_root rm -f /Library/LaunchDaemons/com.dns-bench.auto.plist; removed=1
    fi
  else
    [[ -f /etc/cron.d/dns-bench ]] && { run_root rm -f /etc/cron.d/dns-bench; removed=1 }
    if need crontab && run_root crontab -l 2>/dev/null | grep -q 'dns-bench auto'; then
      run_root crontab -l 2>/dev/null | grep -v 'dns-bench auto' | run_root crontab -; removed=1
    fi
    if [[ -f /etc/systemd/system/dns-bench.timer ]]; then
      run_root systemctl disable --now dns-bench.timer >/dev/null 2>&1
      run_root rm -f /etc/systemd/system/dns-bench.timer /etc/systemd/system/dns-bench.service
      run_root systemctl daemon-reload; removed=1
    fi
  fi
  (( removed )) && print "Schedule removed." || print "No schedule found."
}

cmd_uninstall() {
  cron_remove
  local p removed=0
  for p in /usr/local/bin/dns-bench "$HOME/.local/bin/dns-bench"; do
    if [[ -e $p ]]; then
      if [[ -w ${p:h} ]]; then rm -f "$p"; else run_root rm -f "$p"; fi
      print "Removed $p"; removed=1
    fi
  done
  (( removed )) || print "No installed copy found."
}

remote_version() {   # remote_version FILE -> VERSION= value from a downloaded script
  sed -n 's/^VERSION=\([0-9][0-9.]*\).*/\1/p' "$1" 2>/dev/null | head -1
}

cmd_update() {
  local check=0 force=0 a url=${UPDATE_URL} tmpf remote_ver backup inst
  for a in "$@"; do
    case "$a" in
      --check|-c) check=1 ;;
      --force|-f) force=1 ;;
      *) die "unknown update option: $a (use: update [--check] [--force])" ;;
    esac
  done
  [[ -n "$url" ]] || die "no update URL set (edit UPDATE_URL in this script or set DNSBENCH_UPDATE_URL)"
  need curl || die "curl is required for updates"
  tmpf="$TMP/dns-bench.remote"
  print "Fetching $url"
  curl -fsSL -m 30 -o "$tmpf" "$url" 2>/dev/null || die "download failed: $url"
  (( $(wc -c < "$tmpf") > 2000 )) || die "downloaded file is too small to be dns-bench"
  head -n 1 "$tmpf" | grep -q '^#!' || die "downloaded file is not a script (check the URL)"
  grep -q 'dns-bench' "$tmpf" || die "downloaded file does not look like dns-bench (check the URL)"
  zsh -n "$tmpf" 2>/dev/null || die "downloaded script has a syntax error; not installing it"
  remote_ver=$(remote_version "$tmpf"); [[ -n "$remote_ver" ]] || remote_ver=unknown

  if (( check )); then
    print "  installed: $VERSION"
    print "  remote:    $remote_ver"
    [[ "$remote_ver" == "$VERSION" ]] && print "  ${C_G}up to date${C_0}" || print "  ${C_Y}update available: dns-bench update${C_0}"
    return 0
  fi
  if [[ "$remote_ver" == "$VERSION" ]] && (( ! force )); then
    print "Already up to date ($VERSION). Use --force to reinstall anyway."
    return 0
  fi

  backup="$SELF.$VERSION.bak"
  cp -p "$SELF" "$backup" 2>/dev/null && print "  backup: $backup"
  if [[ -w "$SELF" ]]; then
    cat "$tmpf" > "$SELF" || die "could not write $SELF"
    chmod +x "$SELF"
  else
    run_root cp "$tmpf" "$SELF" && run_root chmod +x "$SELF" || die "could not write $SELF (try sudo)"
  fi
  print "  updated: $VERSION -> $remote_ver"

  inst=$(installed_path)
  if [[ -n "$inst" && "${inst:A}" != "${SELF:A}" ]]; then
    if [[ -w "$inst" ]]; then cat "$tmpf" > "$inst" && chmod +x "$inst"
    else run_root cp "$tmpf" "$inst" && run_root chmod +x "$inst"; fi && print "  updated installed copy: $inst"
  fi
  print "Done. Restart dns-bench to use $remote_ver."
}

cmd_status() {
  detect_net
  print "${C_B}dns-bench $VERSION${C_0}"
  kv "Interface" "${ACTIVE_SERVICE:-unknown} (${ACTIVE_DEV:-none})"
  kv "DNS source" "$(dns_mode_str)"
  kv "DNS in use" "${(j:, :)SYS_DNS:-unknown}"
  build_resolvers
  local d i found=
  for d in $SYS_DNS; do
    i=$(resolver_of_ip "$d")
    [[ -n "$i" ]] && found+="$d = ${${(s:|:)RESOLVERS[$i]}[1]}; "
  done
  [[ -n "$found" ]] && kv "Known resolver" "$found"
  local inst=$(installed_path)
  kv "Installed command" "${inst:-no (run: dns-bench install)}"
  local sch=none
  if (( IS_MAC )); then [[ -f /Library/LaunchDaemons/com.dns-bench.auto.plist ]] && sch="launchd (com.dns-bench.auto)"
  else
    [[ -f /etc/cron.d/dns-bench ]] && sch="cron: $(grep -v '^[#P]' /etc/cron.d/dns-bench | head -1)"
    [[ -f /etc/systemd/system/dns-bench.timer ]] && sch="systemd timer (dns-bench.timer)"
    if [[ "$sch" == none ]] && need crontab; then local cl=$(crontab -l 2>/dev/null | grep 'dns-bench auto'); [[ -n "$cl" ]] && sch="crontab: $cl"; fi
  fi
  kv "Schedule" "$sch"
  [[ -f /var/log/dns-bench.log ]] && kv "Last log lines" "$(tail -n 2 /var/log/dns-bench.log 2>/dev/null | tr '\n' ' ')"
  [[ -f "$HOME/.dns-bench-previous.txt" ]] && kv "Change history" "$HOME/.dns-bench-previous.txt"
}

alog() { print -r -- "[$(date '+%F %T')] auto: $*" }

cmd_auto() {
  QUIET=1; FAST=1; SAMPLES=3; NO_EXT=1
  local prof=${o_prof[-1]:-best} gain=${o_gain[-1]:-20}
  [[ "$prof" == (best|adblock) ]] || die "--profile must be best or adblock"
  [[ "$gain" == <-> ]] || die "--min-gain must be a number"
  detect_net
  [[ -n "$ACTIVE_DEV" ]] || { alog "no default route, skipping"; return 0 }
  build_resolvers
  local kinds="U C" want=U
  [[ "$prof" == adblock ]] && { kinds="A C"; want=A }
  bench_collect "$kinds"
  load_results
  if [[ "$want" == A ]]; then pick_best A needads || { alog "no ad-blocking resolver reachable, keeping current"; return 0 }
  else pick_best U || { alog "no unfiltered resolver reachable, keeping current"; return 0 }; fi

  local cur_idx="" idx cur_score="" cur_ip="${SYS_DNS[1]}" cur_kind="" ri
  for idx in ${(k)NAMEOF}; do [[ "${NAMEOF[$idx]}" == "Current system DNS" ]] && cur_idx=$idx; done
  [[ -n "$cur_idx" ]] && cur_score=${SCORE[$cur_idx]}
  ri=$(resolver_of_ip "$cur_ip"); [[ -n "$ri" ]] && cur_kind=${${(s:|:)RESOLVERS[$ri]}[2]}

  local pick_v4=${${(s:|:)RESOLVERS[$PICK_IDX]}[4]} apply=0 why=
  if [[ "$cur_ip" == "$pick_v4" ]]; then why="already using $PICK_NAME"
  elif [[ "$want" == A && "$cur_kind" != A ]]; then apply=1; why="ad-block profile and current resolver is not an ad-blocker"
  elif [[ -z "$cur_score" ]] || ! is_num "$cur_score" || (( cur_score >= 99999 )); then apply=1; why="current resolver not answering"
  elif (( PICK_SCORE <= cur_score * (100 - gain) / 100.0 )); then apply=1; why="score $PICK_SCORE vs current $cur_score (>= ${gain}% better)"
  else why="current score ${cur_score} vs best ${PICK_SCORE}: gain below ${gain}%"; fi

  if (( apply )); then
    if apply_entry $PICK_IDX; then alog "switched to $PICK_NAME ($why)"
    else alog "FAILED to apply $PICK_NAME"; return 1; fi
  else
    alog "kept ${cur_ip:-current} ($why)"
  fi
}

# =====================================================================
# troubleshooting: dns-bench test DOMAIN
# =====================================================================
# dig_summary SERVER(or empty) NAME TYPE [extra dig args] -> DS_ST DS_MS DS_FLAGS DS_TTL, array DS_ANS
dig_summary() {
  local srv=$1 name=$2 typ=$3 out; shift 3
  if [[ -n "$srv" ]]; then out=$(dig @"$srv" "$name" "$typ" +tries=1 +time=3 +stats "$@" 2>/dev/null)
  else out=$(dig "$name" "$typ" +tries=1 +time=3 +stats "$@" 2>/dev/null); fi
  DS_ANS=(); DS_TTL=-; DS_FLAGS=; DS_MS=-
  if [[ -z "$out" || "$out" == *"connection timed out"* || "$out" == *"no servers could be reached"* ]]; then DS_ST=TIMEOUT; return; fi
  DS_ST=$(print -r -- "$out" | sed -n 's/.*status: \([A-Z]*\).*/\1/p' | head -1)
  DS_MS=$(print -r -- "$out" | awk '/Query time:/ {print $4; exit}')
  DS_FLAGS=$(print -r -- "$out" | sed -n 's/.*flags: \([a-z ]*\);.*/\1/p' | head -1)
  DS_ANS=(${(f)"$(print -r -- "$out" | awk -v t="$typ" '$0 !~ /^;/ && $3=="IN" && $4==t {print $5}')"})
  DS_TTL=$(print -r -- "$out" | awk -v t="$typ" '$0 !~ /^;/ && $3=="IN" && $4==t {print $2; exit}')
  [[ -z "$DS_TTL" ]] && DS_TTL=-
  [[ -z "$DS_MS" ]] && DS_MS=-
}

is_blockip() { [[ "$1" == (0.0.0.0|127.0.0.1|::|::1|146.112.61.*) ]] }

cmd_test() {
  local dom=${1:-$DOMAIN_ARG}
  [[ -n "$dom" ]] || die "usage: dns-bench test DOMAIN"
  dom=${dom%.}
  [[ "$dom" =~ '^[A-Za-z0-9._-]+$' ]] || die "invalid domain"
  detect_net
  [[ -n "$ACTIVE_DEV" ]] || die "no default route: you appear to be offline"

  local -a TNAME TIP VERD OKIPS OKNAMES
  TNAME=("System resolver (${SYS_DNS[1]:-default})"); TIP=("")
  (( GW_DNS )) && { TNAME+=("Router ($GATEWAY)"); TIP+=("$GATEWAY") }
  TNAME+=("Cloudflare" "Google" "Quad9" "OpenDNS" "AdGuard (ads)" "Cloudflare Malware")
  TIP+=("1.1.1.1" "8.8.8.8" "9.9.9.9" "208.67.222.222" "94.140.14.14" "1.1.1.2")
  local x
  for x in ${(s:,:)EXTRA_RES}; do TNAME+=("custom $x"); TIP+=("$x"); done

  section "Troubleshooting: $dom"
  print "  ${C_D}1) A record via ${#TIP} resolvers${C_0}"
  print -n "${C_B}"; cell "  Resolver" 32; cell "Status" 10; cell "Time" 9; cell "TTL" 7; cell "Answer" 40; print "${C_0}"
  local i st col ips shown extra n sysok=0 sysidx=1 anyok=0 first_ok=""
  local -A SETOF
  for (( i = 1; i <= ${#TIP}; i++ )); do
    dig_summary "${TIP[$i]}" "$dom" A
    st=$DS_ST; ips=${(j:,:)${(o)DS_ANS}}
    if [[ "$st" == NOERROR && -z "$ips" ]]; then st=NODATA; fi
    if [[ "$st" == NOERROR ]] && [[ -n "$ips" ]] && is_blockip "${DS_ANS[1]}"; then st=BLOCKED; fi
    case "$st" in NOERROR) col=$C_G ;; NODATA|BLOCKED) col=$C_Y ;; *) col=$C_R ;; esac
    n=${#DS_ANS}; shown=${(j:, :)${(@)DS_ANS[1,3]}}; (( n > 3 )) && shown+=" +$(( n - 3 ))"
    cell "  ${TNAME[$i]}" 32; cell "$st" 10 "$col"; ms_cell "$DS_MS" 9; cell "$DS_TTL" 7 "$C_D"; cell "${shown:--}" 40; print
    SETOF[$i]="$st|$ips"
    if [[ "$st" == NOERROR ]]; then
      (( anyok++ )); OKNAMES+=("${TNAME[$i]}"); OKIPS+=("$ips")
      [[ -z "$first_ok" ]] && first_ok=$i
      (( i == 1 )) && sysok=1
    fi
  done

  # verdict logic
  local failing=() v
  for (( i = 1; i <= ${#TIP}; i++ )); do
    st=${SETOF[$i]%%|*}
    [[ "$st" == NOERROR ]] && continue
    failing+=("$i")
  done
  if (( anyok == 0 )); then
    VERD+=("${C_R}No resolver returned an address.${C_0} Either $dom doesn't exist (check spelling), its authoritative servers are down/misconfigured (see step 3), or the name has no A record (try AAAA/CNAME in step 2).")
  else
    if (( ! sysok )); then
      VERD+=("${C_R}Your system resolver fails (${SETOF[1]%%|*}) while public resolvers answer.${C_0} The problem is your local DNS (router/ISP/VPN/filter). Try: dns-bench set cloudflare")
    fi
    for i in $failing; do
      (( i == 1 )) && continue
      st=${SETOF[$i]%%|*}
      case "$st" in
        NXDOMAIN) v="says NXDOMAIN while others resolve it: filtered, hijacked, or a stale negative cache" ;;
        SERVFAIL) v="SERVFAIL: DNSSEC validation failure or broken upstream path from that resolver" ;;
        REFUSED)  v="REFUSED: that resolver won't serve you (policy/ACL)" ;;
        TIMEOUT)  v="no answer: unreachable or port 53 blocked from your network" ;;
        BLOCKED)  v="returns a block address: the domain is on that resolver's blocklist" ;;
        NODATA)   v="answers but with no A record" ;;
        *) v="status $st" ;;
      esac
      VERD+=("${TNAME[$i]}: $v")
    done
    # consistency among OK resolvers
    local -A GROUPS_; local k
    for (( i = 1; i <= ${#OKIPS}; i++ )); do GROUPS_[${OKIPS[$i]}]+="${OKNAMES[$i]}; "; done
    if (( ${#GROUPS_} > 1 )); then
      VERD+=("${C_Y}Resolvers return different address sets${C_0} (normal for CDNs/geo-DNS; suspicious for a single-host site):")
      for k in ${(k)GROUPS_}; do VERD+=("    ${k:0:60}  <-  ${GROUPS_[$k]}"); done
    elif (( anyok > 1 )); then
      VERD+=("${C_G}All answering resolvers agree.${C_0}")
    fi
  fi

  # ---- 2) records
  print "\n  ${C_D}2) records (via ${TNAME[${first_ok:-1}]})${C_0}"
  local t lines srv=${TIP[${first_ok:-1}]}
  for t in ${=REC_TYPES}; do
    lines=(${(f)"$( ( [[ -n "$srv" ]] && dig @"$srv" "$dom" "$t" +short +tries=1 +time=3 || dig "$dom" "$t" +short +tries=1 +time=3 ) 2>/dev/null | head -6)"})
    if (( ${#lines} )); then
      printf "  %-6s %s\n" "$t" "${lines[1][1,100]}"
      for v in ${lines[2,-1]}; do printf "  %-6s %s\n" "" "${v[1,100]}"; done
    else
      printf "  %-6s ${C_D}-${C_0}\n" "$t"
    fi
  done

  # ---- 3) authoritative
  print "\n  ${C_D}3) authoritative name servers${C_0}"
  local zone
  zone=$(dig SOA "$dom" +noall +answer +authority +time=3 +tries=1 2>/dev/null | awk '$4=="SOA" {print $1; exit}')
  zone=${zone%.}
  if [[ -z "$zone" ]]; then
    print "  could not find the zone (SOA) for $dom"
    VERD+=("Couldn't determine the zone's SOA: the domain may not exist or its DNS is badly broken.")
  else
    local -a NS; NS=(${(f)"$(dig +short NS "$zone" +time=3 +tries=1 2>/dev/null | head -4)"})
    print "  zone: $zone | ${#NS} name server(s)"
    print -n "${C_B}"; cell "  Name server" 32; cell "Status" 10; cell "Time" 9; cell "AA" 5; cell "Serial" 12; cell "Answer" 28; print "${C_0}"
    local ns nip serial ans_a aa; local -a SERIALS
    for ns in $NS; do
      nip=$(dig +short A "$ns" +time=3 +tries=1 2>/dev/null | grep -E '^[0-9.]+$' | head -1)
      if [[ -z "$nip" ]]; then cell "  ${ns%.}" 32; cell "no-A" 10 "$C_R"; print; continue; fi
      dig_summary "$nip" "$dom" A +norecurse
      aa=no; [[ " $DS_FLAGS " == *" aa "* ]] && aa=yes
      ans_a=${(j:, :)${(@)DS_ANS[1,2]}}
      serial=$(dig @"$nip" SOA "$zone" +short +tries=1 +time=3 2>/dev/null | awk '{print $3; exit}')
      [[ -n "$serial" ]] && SERIALS+=("$serial")
      cell "  ${ns%.}" 32; cell "$DS_ST" 10 "$([[ $DS_ST == NOERROR ]] && print $C_G || print $C_R)"; ms_cell "$DS_MS" 9; cell "$aa" 5; cell "${serial:--}" 12; cell "${ans_a:--}" 28; print
      [[ "$DS_ST" == TIMEOUT ]] && VERD+=("Authoritative server ${ns%.} ($nip) is not answering.")
    done
    if (( ${#${(u)SERIALS}} > 1 )); then VERD+=("${C_Y}Authoritative servers have different SOA serials (${(j:, :)${(u)SERIALS}}):${C_0} zone changes are still propagating or a secondary is out of sync.")
    elif (( ${#SERIALS} > 1 )); then VERD+=("${C_G}Authoritative servers are in sync (serial ${SERIALS[1]}).${C_0}"); fi
  fi

  # ---- 4) DNSSEC
  print "\n  ${C_D}4) DNSSEC${C_0}"
  local ds signed=no
  [[ -n "$zone" ]] && ds=$(dig +short DS "$zone" @1.1.1.1 +time=3 +tries=1 2>/dev/null | head -1)
  [[ -n "$ds" ]] && signed=yes
  dig_summary 1.1.1.1 "$dom" A +dnssec
  local valid=no; [[ " $DS_FLAGS " == *" ad "* ]] && valid=yes
  kv "Zone signed (DS record)" "$signed"
  kv "Validated by 1.1.1.1" "$valid"
  if [[ "$signed" == yes && "$DS_ST" == SERVFAIL ]]; then VERD+=("${C_R}DNSSEC is broken for this zone (SERVFAIL on a validating resolver).${C_0} Check the DS record at the registrar vs the zone's keys.")
  elif [[ "$signed" == yes && "$valid" == no && "$DS_ST" == NOERROR ]]; then VERD+=("Zone has a DS record but 1.1.1.1 didn't validate it: possibly a partial/expired signature.")
  fi

  # ---- 5) reachability
  print "\n  ${C_D}5) reachability${C_0}"
  local -a V4 V6; local ip ms
  if [[ -n "$first_ok" ]]; then V4=(${(s:,:)OKIPS[1]}); fi
  (( ${#OKIPS} )) && V4=(${(s:,:)OKIPS[1]})
  dig_summary "$srv" "$dom" AAAA; V6=("${DS_ANS[@]}")
  for ip in ${V4[1,3]}; do
    ms=$(tcp_ms "$ip" 443 3) && v="${ms} ms" || v="${C_R}fail${C_0}"
    local m80; m80=$(tcp_ms "$ip" 80 3) && m80="${m80} ms" || m80="${C_R}fail${C_0}"
    printf "  %-40s 443: %-12s 80: %s\n" "$ip" "$v" "$m80"
  done
  for ip in ${V6[1,2]}; do
    ms=$(tcp_ms "$ip" 443 3) && v="${ms} ms" || v="${C_R}fail${C_0}"
    printf "  %-40s 443: %s\n" "$ip" "$v"
  done
  if (( ${#V4} == 0 && ${#V6} == 0 )); then print "  no addresses to test"
  else
    local r rc
    r=$(curl -sS -o /dev/null -m 8 -w '%{http_code} %{time_connect} %{time_appconnect} %{time_total} %{ssl_verify_result} %{remote_ip}' "https://$dom/" 2>"$TMP/curl.err"); rc=$?
    if (( rc == 0 )); then
      local hc tc ta tt sv rip; read -r hc tc ta tt sv rip <<< "$r"
      kv "HTTPS (system resolver)" "HTTP $hc | connect ${tc}s | TLS ${ta}s | total ${tt}s | cert verify: $( [[ $sv == 0 ]] && print ok || print "code $sv") | $rip"
      [[ "$hc" == (4*|5*) ]] && VERD+=("HTTPS answers with HTTP $hc (the server is reachable, the problem is above DNS).")
    else
      local why
      case $rc in 6) why="the system resolver couldn't resolve it" ;; 7) why="connection refused" ;; 28) why="timed out" ;; 35|51|58|60|77) why="TLS/certificate problem" ;; *) why="curl error $rc" ;; esac
      kv "HTTPS (system resolver)" "${C_R}failed: $why${C_0} $(head -c 120 "$TMP/curl.err")"
      VERD+=("HTTPS fetch failed: $why.")
    fi
    if (( ${#V6} )); then
      if curl -6 -sS -o /dev/null -m 6 "https://$dom/" 2>/dev/null; then kv "HTTPS over IPv6" "${C_G}ok${C_0}"
      else kv "HTTPS over IPv6" "${C_Y}failed${C_0} ${C_D}(AAAA exists; if IPv4 works this can cause slow fallbacks)${C_0}"; fi
    fi
  fi
  if [[ -n "${V4[1]}" ]]; then
    local ptr=$(dig +short -x "${V4[1]}" +time=3 +tries=1 2>/dev/null | head -1)
    kv "Reverse DNS of ${V4[1]}" "${ptr:--}"
  fi

  section "Verdict"
  if (( ${#VERD} == 0 )); then print "  ${C_G}Nothing wrong found.${C_0}"
  else for v in "${VERD[@]}"; do print "  - $v"; done; fi
}

# =====================================================================
# flush
# =====================================================================
cmd_flush() {
  flush_dns_cache
  if (( IS_MAC )) || need resolvectl || need systemd-resolve || need nscd; then
    print "  ${C_G}DNS cache flushed.${C_0}"
  else
    print "  No local DNS cache to flush."
    note "This system has no resolvectl, systemd-resolve or nscd; the cache is in the router/upstream, so nothing to do."
  fi
  return 0
}

# =====================================================================
# demo: a complete sample run with fake data (no network, no changes)
# =====================================================================
cmd_demo() {
  local row rank idx name region kind cm jit loss cold score v4p v6m v6p dsec nx tcp dot doh ads pop rc
  local -a DEMO_ROWS DEMO_FEATURES DEMO_REGIONS
  local -i demo_quick=0
  (( $#o_q )) && demo_quick=1

  print "${C_B}dns-bench $VERSION${C_0}  $(date '+%Y-%m-%d %H:%M:%S %Z')  |  target: example.com  |  samples: 5"

  section "Network"
  kv "Host" "demo-mac | macOS 15.3 | arm64"
  kv "Active interface" "Wi-Fi (en0)"
  kv "Link" "866 Mb/s"
  kv "MAC / MTU" "02:00:00:00:00:01 / 1500"
  kv "Local IPv4" "192.0.2.42 /24"
  kv "Local IPv6" "2001:db8:4::42 ${C_D}(1 global address)${C_0}"
  kv "Gateway" "192.0.2.1"
  kv "DHCP server" "192.0.2.1"
  kv "System proxy" "none"
  kv "VPN connected" "no"
  kv "Gateway latency" "3.1 ms, loss 0%"
  kv "System DNS (in use)" "1.1.1.1, 1.0.0.1"
  kv "DNS source" "automatic (DHCP/router)"
  kv "Router answers DNS" "yes"
  kv "Public IPv4" "203.0.113.42"
  kv "Public IPv6" "2001:db8:4::42"
  kv "Location" "Amsterdam, North Holland, Netherlands [EU]"
  kv "ISP / ASN" "Example ISP (AS64500)"
  kv "Time zone" "Europe/Amsterdam"
  kv "Nearest Cloudflare PoP" "AMS (WARP: off)"
  kv "System resolver egress IP" "203.0.113.42"
  kv "DNS interception" "${C_G}none detected${C_0}"
  kv "Captive portal" "${C_G}no${C_0}"
  kv "IPv6 to resolvers" "working"

  section "DNS benchmark: 53 resolvers"
  print "  Cached = median of 5 queries for example.com | Cold = median of 3 random uncached names | Score = (cached + 2*cold)/3 + 3*loss%"
  note "Probing up to $MAXJOBS resolvers at once"

  # rank|#|provider|rgn|kind|cached|jitter|loss|cold|score|v4 ping|v6 dns|v6 ping
  DEMO_ROWS=(
    "1|1|Cloudflare|GL|U|14|1.2|0|31|22.0|12.4|15|12.8"
    "2|4|Google Public DNS|GL|U|16|1.8|0|34|24.7|13.1|17|13.5"
    "3|6|Quad9 (Unfiltered)|GL|U|18|2.1|0|38|27.3|14.6|19|14.9"
    "4|11|AdGuard Unfiltered|GL|U|21|2.6|0|44|31.7|15.2|22|15.6"
    "5|12|Control D Unfiltered|GL|U|23|3.0|0|47|34.3|16.8|24|17.1"
    "6|15|NextDNS (Anycast)|GL|U|27|3.4|0|52|38.7|17.9|28|18.2"
    "7|23|Verisign Public DNS|GL|U|31|4.1|0|58|43.7|19.4|31|19.8"
    "8|52|Router / Gateway|LAN|C|2.4|0.6|0|39|68.8|1.9|-|1.8"
    "9|53|Current system DNS|LAN|C|14|1.5|0|36|23.0|12.6|15|12.9"
  )
  print
  print -n "${C_B}"
  cell "Rank" 5; cell "#" 4; cell "Provider" 27; cell "Rgn" 4; cell "Kind" 5
  cell "Cached" 9; cell "Jitter" 8; cell "Loss" 6; cell "Cold" 9; cell "Score" 7
  cell "v4 ping" 9; cell "v6 DNS" 9; cell "v6 ping" 9
  print "${C_0}"
  print "  ${C_D}-------------------------------------------------------------------------------------------------------------${C_0}"
  for row in $DEMO_ROWS; do
    IFS="|" read -r rank idx name region kind cm jit loss cold score v4p v6m v6p <<< "$row"
    rc=""; (( rank == 1 )) && rc=$C_B
    cell "$rank" 5 "$rc"; cell "$idx" 4; cell "$name" 27 "$rc"; cell "$region" 4; cell "$kind" 5
    ms_cell "$cm" 9; cell "${jit} ms" 8 "$C_D"; cell "${loss}%" 6 "$C_D"; ms_cell "$cold" 9
    cell "$score" 7 "$C_B"
    ms_cell "$v4p" 9; ms_cell "$v6m" 9; ms_cell "$v6p" 9
    print
  done
  print "  ${C_D}Kind: U unfiltered | F filters/blocks content | A blocks ads | C your current/local resolver (baseline, never auto-selected)${C_0}"

  if (( ! demo_quick )); then
    # #|provider|dnssec|nxdomain|tcp53|dot853|443|blocks ads|pop
    DEMO_FEATURES=(
      "1|Cloudflare|yes|ok|yes|yes|yes|no|ams"
      "4|Google Public DNS|yes|ok|yes|yes|yes|no|ams01"
      "6|Quad9 (Unfiltered)|yes|ok|yes|yes|yes|no|fra"
      "11|AdGuard Unfiltered|yes|ok|yes|yes|yes|no|ams"
      "12|Control D Unfiltered|yes|ok|yes|yes|yes|no|ams"
      "15|NextDNS (Anycast)|yes|ok|yes|yes|yes|no|ams"
      "23|Verisign Public DNS|yes|ok|yes|no|yes|no|-"
      "52|Router / Gateway|?|ok|yes|no|yes|no|-"
      "53|Current system DNS|yes|ok|yes|no|yes|no|-"
    )
    section "Features & security"
    print -n "${C_B}"
    cell "#" 4; cell "Provider" 27; cell "DNSSEC" 8; cell "NXDOMAIN" 10; cell "TCP/53" 8; cell "DoT:853" 9; cell "443 open" 9; cell "Blocks ads" 11; cell "PoP / node" 24
    print "${C_0}"
    print "  ${C_D}-------------------------------------------------------------------------------------------------------------${C_0}"
    for row in $DEMO_FEATURES; do
      IFS="|" read -r idx name dsec nx tcp dot doh ads pop <<< "$row"
      cell "$idx" 4; cell "$name" 27
      yn_cell "$dsec" 8 yes; yn_cell "$nx" 10 ok; yn_cell "$tcp" 8 yes; yn_cell "$dot" 9 yes; yn_cell "$doh" 9 yes
      cell "$ads" 11 "$C_D"; cell "$pop" 24 "$C_D"
      print
    done
    print "  ${C_D}DNSSEC: validates signatures | NXDOMAIN: HIJACK = rewrites non-existent names | DoT/443: port reachable from your network${C_0}"
    print "  ${C_D}Blocks ads: 2 of 3 known ad domains refused/null-routed | PoP: anycast node that answered you (when exposed)${C_0}"
  fi

  section "Best unfiltered resolver per region"
  DEMO_REGIONS=(
    "Global anycast|Cloudflare|14"
    "North America|Verisign Public DNS|31"
    "Europe|DNS4EU (Unfiltered)|26"
    "Asia|AliDNS|92"
  )
  for row in $DEMO_REGIONS; do
    IFS="|" read -r name region cm <<< "$row"
    printf "  %-16s %-26s %s ms\n" "$name" "$region" "$cm"
  done

  section "Speed test"
  note "Cloudflare edge (OVH fallback), 4 parallel streams, IPv4. Measures the link itself, not your DNS choice."
  print "  Latency to 1.1.1.1        14.2 ms   (jitter 1.1 ms, 0% loss)"
  print "  Download                  482.6 Mbps  (241 MB in 4.0s)"
  print "  Upload                    211.4 Mbps  (84 MB in 3.2s)"
  note "Download is 2.3x upload."

  section "Summary"
  kv "Fastest DNS (unfiltered)" "#1 Cloudflare: cached 14 ms, score 22.0"
  kv "Your current DNS" "Current system DNS: cached 14 ms, cold 36 ms, score 23.0"
  kv "" "${C_G}already near the top${C_0}"

  section "Connection score"
  SCORE_V=(dns 84 latency 91 speed 71 privacy 64 stability 88 total 80)
  SCORE_D=(
    dns       "cached 14 ms, cold 36 ms, 1% loss"
    latency   "14.2 ms, jitter 1.1 ms"
    speed     "down 482 Mbps, up 211 Mbps"
    privacy   "NXDOMAIN ok, DNSSEC yes, DoT yes"
    stability "1% DNS loss, 0% ICMP loss"
  )
  score_render
  note "Bands are this tool's rubric for a healthy connection, not a survey of the internet."

  print
  note "Demo data. Nothing was probed and no DNS settings were read."
  return 0
}

# =====================================================================
# network diagnostics (3.3): ports http tls trace asn ptr mtu leak
#                             propagation ecs ifaces listen wifi doctor
# =====================================================================
# Every external call is bounded and non-fatal: a missing binary or a refused
# connection prints one clear line and moves on, never aborting the run.
# doctor is the only command allowed to fail loudly (exit 1).

ms_of() { perl -e 'printf "%d", $ARGV[0]*1000+0.5' "$1" 2>/dev/null; }   # ms_of SECONDS

port_service() {
  case "$1" in
    22) print ssh ;; 53) print dns ;; 80) print http ;; 443) print https ;;
    853) print dot ;; 3306) print mysql ;; 5432) print postgres ;; 6379) print redis ;;
    8080) print http-alt ;; *) print - ;;
  esac
}

# tcp_state HOST PORT [TIMEOUT] -> "open MS" | "closed -" | "filtered -"
tcp_state() {
  local out
  out=$(perl -MIO::Socket::IP -MTime::HiRes=time -e '
    my ($h,$p,$to)=@ARGV; my $t=time;
    my $s=IO::Socket::IP->new(PeerHost=>$h,PeerPort=>$p,Timeout=>$to);
    if ($s) { close $s; printf "open %d\n", (time-$t)*1000+0.5; exit 0 }
    my $e="$!"; print (($e =~ /refused/i) ? "closed -\n" : "filtered -\n");
  ' "$1" "$2" "${3:-2}" 2>/dev/null)
  print -r -- "${out:-filtered -}"
}

pub_ip() {   # public IPv4, best effort, bounded
  local ip=
  ip=$(curl -4 -s -m 4 https://1.1.1.1/cdn-cgi/trace 2>/dev/null | awk -F= '/^ip=/ {print $2; exit}')
  [[ -z "$ip" ]] && ip=$(dig -4 +short myip.opendns.com @resolver1.opendns.com +time=2 +tries=1 2>/dev/null | tail -1)
  print -r -- "$ip"
}

resolve_v4() {   # resolve_v4 HOST|IP -> first IPv4
  local ip=$1
  [[ "$ip" == <->.<->.<->.<-> ]] && { print -r -- "$ip"; return; }
  dig +short A "$ip" +time=2 +tries=1 2>/dev/null | grep -E '^[0-9.]+$' | head -1
}

cmd_ports() {
  local host=$1 ports_arg=$2
  [[ -n "$host" ]] || die "usage: dns-bench ports HOST [PORTS]"
  [[ "$host" =~ '^[A-Za-z0-9._:-]+$' ]] || die "invalid host"
  local -a plist
  if [[ -z "$ports_arg" ]]; then
    plist=(22 53 80 443 853 3306 5432 6379 8080)
  else
    local norm=${ports_arg//,/ }
    plist=(${=norm})
  fi
  local p bad=
  for p in $plist; do [[ "$p" == <1-65535> ]] || bad=$p; done
  [[ -z "$bad" ]] || die "invalid port: $bad (expected 1-65535)"
  section "TCP ports: $host"
  print -n "${C_W}"; cell "  Port" 8; cell "State" 11; cell "Connect" 10; cell "Service" 13; print "${C_0}"
  local -a pids; local tmo=2
  for p in $plist; do ( tcp_state "$host" "$p" "$tmo" > "$TMP/port.$p" ) & pids+=($!); done
  wait $pids
  local state ms line nopen=0
  for p in $plist; do
    line=$(<"$TMP/port.$p" 2>/dev/null)
    state=${line%% *}; ms=${line##* }
    cell "  $p" 8
    case "$state" in
      open)     cell "open" 11 "$C_OK"; ms_cell "$ms" 10; (( nopen++ )) ;;
      closed)   cell "closed" 11 "$C_D"; cell "-" 10 "$C_D" ;;
      *)        cell "filtered" 11 "$C_WARN"; cell "-" 10 "$C_D" ;;
    esac
    cell "$(port_service "$p")" 13 "$C_D"; print
  done
  note "$nopen of ${#plist} open. open = handshake completed, closed = refused, filtered = no reply (drop/firewall)."
}

cmd_http() {
  local url=$1
  [[ -n "$url" ]] || die "usage: dns-bench http URL"
  [[ "$url" == (http|https)://* ]] || url="https://$url"
  [[ "$url" =~ '^https?://[^[:space:]]+$' ]] || die "invalid URL"
  need curl || die "curl not found"
  section "HTTP: $url"
  local w out rc
  w='%{http_code}|%{time_namelookup}|%{time_connect}|%{time_appconnect}|%{time_starttransfer}|%{time_total}|%{size_download}|%{num_redirects}|%{url_effective}|%{remote_ip}'
  out=$(curl -sS -o /dev/null -m 25 --connect-timeout 8 -L -w "$w" "$url" 2>"$TMP/http.err"); rc=$?
  if (( rc != 0 )); then
    print "  ${C_ERR}request failed${C_0} (curl exit $rc)"
    [[ -s "$TMP/http.err" ]] && sed 's/^/  /' "$TMP/http.err" | head -3
    return 1
  fi
  local code dns_t con_t tls_t ttfb_t total_t size redirs final rip
  IFS='|' read -r code dns_t con_t tls_t ttfb_t total_t size redirs final rip <<< "$out"
  local ccol=$C_OK
  [[ "$code" == 3* ]] && ccol=$C_C
  [[ "$code" == 4* ]] && ccol=$C_WARN
  [[ "$code" == (5*|000) ]] && ccol=$C_ERR
  kv "HTTP status" "${ccol}${code}${C_0}"
  kv "Final URL" "${final:-$url}"
  kv "Remote IP" "${rip:--}"
  print -n "${C_W}"; cell "  Phase" 14; cell "ms" 10; print "${C_0}"
  local k v
  for k in dns connect tls ttfb total; do
    case "$k" in
      dns) v=$dns_t ;; connect) v=$con_t ;; tls) v=$tls_t ;;
      ttfb) v=$ttfb_t ;; total) v=$total_t ;;
    esac
    cell "  $k" 14
    if [[ "$k" == tls && "$v" == 0* && "$url" == http://* ]]; then cell "-" 10 "$C_D"
    else ms_cell "$(ms_of "$v")" 10; fi
    print
  done
  kv "Size" "${size} bytes"
  kv "Redirects" "${redirs:-0}"
  note "dns = name lookup, connect = TCP, tls = handshake, ttfb = first byte, total = whole body."
}

cmd_tls() {
  local target=$1 host port raw info
  [[ -n "$target" ]] || die "usage: dns-bench tls HOST[:PORT]"
  if [[ "$target" == \[*\]:* ]]; then
    host=${target%]:*}; host=${host#[}; port=${target##*:}
  elif [[ "$target" == *:* && "$target" != *::* ]]; then
    host=${target%:*}; port=${target##*:}
  else
    host=$target; port=443
  fi
  [[ "$port" == <1-65535> ]] || die "invalid port: $port"
  need openssl || die "openssl not found (install openssl; it normally ships with macOS and most distros)"
  section "TLS: $host:$port"
  raw=$( { perl -e 'alarm 12; exec @ARGV' openssl s_client -connect "$host:$port" -servername "$host" -showcerts </dev/null; } 2>&1 )
  if [[ "$raw" != *"BEGIN CERTIFICATE"* ]]; then
    print "  ${C_ERR}handshake failed${C_0} on $host:$port"
    print -r -- "$raw" | grep -iE 'error|refused|timed out|unable|no route' | head -3 | sed 's/^/  /'
    return 1
  fi
  print -r -- "$raw" | awk '/BEGIN CERTIFICATE/{f=1} f{print} /END CERTIFICATE/{exit}' > "$TMP/tls.pem"
  info=$(openssl x509 -in "$TMP/tls.pem" -noout -subject -issuer -startdate -enddate -ext subjectAltName 2>/dev/null)
  local cn issuer nb na days sans proto
  cn=$(print -r -- "$info" | sed -n 's/^subject=//p' | sed 's/.*CN *= *//' | cut -d, -f1)
  issuer=$(print -r -- "$info" | sed -n 's/^issuer=//p')
  nb=$(print -r -- "$info" | sed -n 's/^notBefore=//p')
  na=$(print -r -- "$info" | sed -n 's/^notAfter=//p')
  sans=$(print -r -- "$info" | grep -o 'DNS:' | wc -l | tr -d ' ')
  days=$(perl -MTime::Local=timegm -e '
    my $s=shift; my %m=(Jan=>0,Feb=>1,Mar=>2,Apr=>3,May=>4,Jun=>5,Jul=>6,Aug=>7,Sep=>8,Oct=>9,Nov=>10,Dec=>11);
    my ($mo,$d,$H,$M,$S,$y)=$s=~/([A-Z][a-z]{2})\s+(\d+)\s+(\d+):(\d+):(\d+)\s+(\d{4})/ or exit 1;
    my $e=timegm($S,$M,$H,$d,$m{$mo},$y); printf "%d", int(($e-time)/86400)' "$na" 2>/dev/null)
  proto=$(print -r -- "$raw" | sed -n 's/.*Protocol *: *\([^ ,]*\).*/\1/p' | head -1)
  [[ -z "$proto" ]] && proto=$(print -r -- "$raw" | sed -n 's/^New, \([^,]*\),.*/\1/p' | head -1)
  kv "Subject CN" "${cn:-unknown}"
  kv "Issuer" "${issuer:--}"
  kv "Valid from" "${nb:--}"
  kv "Valid until" "${na:--}"
  if [[ "$days" == <-> ]]; then
    if (( days < 0 )); then kv "Days left" "${C_ERR}expired ${days#-} days ago${C_0}"
    elif (( days < 21 )); then kv "Days left" "${C_WARN}${days} (expires soon)${C_0}"
    else kv "Days left" "${C_OK}${days}${C_0}"; fi
  else
    kv "Days left" "?"
  fi
  kv "SAN entries" "${sans:-0}"
  kv "Protocol" "${proto:-unknown}"
  note "s_client connects to $host:$port and reads the leaf certificate; no verification is performed."
}

cmd_trace() {
  local host=$1 out tool=
  [[ -n "$host" ]] || die "usage: dns-bench trace HOST"
  [[ "$host" =~ '^[A-Za-z0-9._:-]+$' ]] || die "invalid host"
  if need traceroute; then
    tool=traceroute
    out=$( { perl -e 'alarm 30; exec @ARGV' traceroute -n -q 1 -w 1 -m 16 "$host"; } 2>/dev/null )
  elif need tracepath; then
    tool=tracepath
    out=$( { perl -e 'alarm 30; exec @ARGV' tracepath -n -m 16 "$host"; } 2>/dev/null )
  else
    die "neither traceroute nor tracepath is installed (install traceroute)"
  fi
  section "Path to $host ($tool)"
  if [[ -z "$out" ]]; then print "  ${C_ERR}no output${C_0}: $tool could not run (needs root on some systems)"; return 1; fi
  print -n "${C_W}"; cell "  Hop" 6; cell "Address" 40; cell "RTT" 10; print "${C_0}"
  local line hop addr rtt n=0
  while IFS= read -r line; do
    [[ "$line" == [[:space:]]*<->* ]] || continue
    hop=${${(s: :)line}[1]}
    addr=${${(s: :)line}[2]}
    [[ "$addr" == "*" ]] && addr="-"
    rtt=$(print -r -- "$line" | awk '{for(i=3;i<=NF;i++) if($i=="ms"){print $(i-1); exit}}')
    cell "  $hop" 6; cell "$addr" 40 "$C_D"
    if is_num "$rtt"; then ms_cell "$rtt" 10; else cell "-" 10 "$C_D"; fi
    print
    (( n++ ))
  done <<< "$out"
  (( n )) || print "  no hops parsed (the target may be local or unreachable)"
}

cmd_asn() {
  local q=$1 ip origin asn prefix cc reg alloc name org
  [[ -n "$q" ]] || die "usage: dns-bench asn HOST|IP"
  ip=$(resolve_v4 "$q")
  [[ -n "$ip" ]] || die "could not resolve $q to an IPv4 address"
  section "ASN: $q ($ip)"
  origin=$(dig +short TXT "$ip.origin.asn.cymru.com" +time=3 +tries=1 2>/dev/null | head -1 | tr -d '"')
  if [[ -z "$origin" ]]; then print "  ${C_ERR}no Team Cymru answer${C_0} (offline, or DNS TXT blocked)"; return 1; fi
  IFS='|' read -r asn prefix cc reg alloc <<< "${origin// /}"
  name=$(dig +short TXT "AS${asn}.asn.cymru.com" +time=3 +tries=1 2>/dev/null | head -1 | tr -d '"')
  org=${name#*|}; org=${org#*|}; org=${org#*|}; org=${org#*|}
  kv "ASN" "AS${asn}"
  kv "BGP prefix" "${prefix:--}"
  kv "Country" "${cc:--}"
  kv "Registry" "${reg:--}"
  kv "Allocated" "${alloc:--}"
  kv "Org" "${org:--}"
  note "Source: Team Cymru DNS (origin.asn.cymru.com / asn.cymru.com). IPv4 only."
}

cmd_ptr() {
  local ip=$1 n typ a ok
  [[ -n "$ip" ]] || die "usage: dns-bench ptr IP"
  section "Reverse DNS: $ip"
  local -a names
  names=(${(f)"$(dig +short -x "$ip" +time=3 +tries=1 2>/dev/null)"})
  if (( ! ${#names} )); then
    print "  ${C_WARN}no PTR record${C_0} for $ip"
    note "Many cloud and residential ranges simply have no reverse DNS; that is not an error."
    return 0
  fi
  print -n "${C_W}"; cell "  PTR name" 46; cell "FCrDNS" 9; cell "Forward answer" 32; print "${C_0}"
  for n in $names; do
    n=${n%.}
    typ=A; [[ "$ip" == *:* ]] && typ=AAAA
    dig_summary "" "$n" "$typ"
    ok=no
    for a in $DS_ANS; do [[ "$a" == "$ip" ]] && ok=yes; done
    cell "  $n" 46
    yn_cell "$ok" 9 yes
    cell "${(j:, :)${(@)DS_ANS[1,2]:--}}" 32 "$C_D"; print
  done
  note "FCrDNS = the PTR name resolves forward to the same address. yes means mail servers will trust it more."
}

cmd_leak() {
  local pub sys_egress r egress verdict vcol sys_bad=0 res_bad=0 total=0
  local -A ROWNER
  ROWNER=(1.1.1.1 Cloudflare 1.0.0.1 Cloudflare 8.8.8.8 Google 8.8.4.4 Google
          9.9.9.9 Quad9 149.112.112.112 Quad9 208.67.222.222 OpenDNS
          94.140.14.14 AdGuard 77.88.8.8 Yandex)
  detect_net
  section "DNS leak check"
  pub=$(pub_ip)
  kv "Your public IP" "${pub:-unknown (offline or privacy mode)}"
  sys_egress=$(dig +short whoami.akamai.net +time=3 +tries=1 2>/dev/null | tail -1)
  kv "System resolver egress" "${sys_egress:--}"
  if [[ -n "$pub" && -n "$sys_egress" ]]; then
    if [[ "$pub" == "$sys_egress" ]]; then
      kv "System verdict" "${C_OK}same network as you${C_0}"
    else
      kv "System verdict" "${C_WARN}different network${C_0}: queries leave via an upstream/ISP resolver (VPN, router or transparent proxy)"
      sys_bad=1
    fi
  fi
  print ""
  print -n "${C_W}"; cell "  Resolver" 22; cell "Egress IP" 20; cell "Verdict" 34; print "${C_0}"
  local -a rlist
  rlist=(${SYS_DNS[@]})
  (( GW_DNS )) && [[ "$GATEWAY" != "${SYS_DNS[1]}" ]] && rlist+=("$GATEWAY")
  if (( ! ${#rlist} )); then print "  no configured resolvers found"; return 0; fi
  local shown=0
  for r in $rlist; do
    [[ "$r" == *.*.*.* ]] || continue
    egress=$(dig @"$r" +short whoami.akamai.net +time=2 +tries=1 2>/dev/null | tail -1)
    (( total++ ))
    cell "  $r" 22
    cell "${egress:--}" 20 "$C_D"
    vcol=$C_D
    if [[ -z "$egress" ]]; then
      verdict="no answer"
    elif [[ -n "$pub" && "$egress" == "$pub" ]]; then
      verdict="your own network"; vcol=$C_OK
    elif [[ -n "${ROWNER[$r]}" ]]; then
      verdict="${ROWNER[$r]}'s own network"
    elif [[ "$r" == (10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*) ]]; then
      verdict="local resolver, forwards upstream"; vcol=$C_WARN; (( res_bad++ ))
    elif [[ "$egress" == (10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*) ]]; then
      verdict="private egress"; vcol=$C_WARN; (( res_bad++ ))
    else
      verdict="upstream network"
    fi
    cell "$verdict" 34 "$vcol"
    print
    (( ++shown >= 8 )) && { [[ $shown -lt ${#rlist} ]] && note "showing the first $shown of ${#rlist} configured resolvers"; break; }
  done
  print ""
  if (( sys_bad || res_bad )); then
    kv "Result" "${C_WARN}mismatch: $(( sys_bad + res_bad )) path(s) differ from your public network${C_0}"
  else
    kv "Result" "${C_OK}no mismatch detected${C_0}"
  fi
  note "A public resolver answering from its own network is expected. A local resolver whose egress is not yours is the one worth investigating."
}

cmd_propagation() {
  local dom=$1 typ=${2:-A}
  [[ -n "$dom" ]] || die "usage: dns-bench propagation DOMAIN [TYPE]"
  dom=${dom%.}
  [[ "$dom" =~ '^[A-Za-z0-9._-]+$' ]] || die "invalid domain"
  [[ "$typ" =~ '^[A-Za-z0-9]+$' ]] || die "invalid record type"
  typ=${(U)typ}
  local -a RN RIP
  RN=(Cloudflare Google Quad9 OpenDNS AdGuard Yandex AliDNS Quad101)
  RIP=(1.1.1.1 8.8.8.8 9.9.9.9 208.67.222.222 94.140.14.14 77.88.8.8 223.5.5.5 101.101.101.101)
  section "Propagation: $dom $typ"
  print -n "${C_W}"; cell "  Resolver" 16; cell "Status" 11; cell "Time" 9; cell "Answer" 46; print "${C_0}"
  local i st set shown col rawans
  local -A GROUPS
  local -a ORDER ANS
  for (( i = 1; i <= ${#RIP}; i++ )); do
    dig_summary "${RIP[$i]}" "$dom" "$typ"
    st=$DS_ST
    # +short is used for the answer text so MX/SRV keep their full rdata.
    rawans=$(dig @"${RIP[$i]}" "$dom" "$typ" +short +tries=1 +time=3 2>/dev/null)
    ANS=(${(f)rawans})
    set=${(j:,:)${(o)ANS}}
    [[ -z "$set" ]] && set="(no answer)"
    case "$st" in NOERROR) col=$C_OK ;; *) col=$C_ERR ;; esac
    shown=${(j:, :)${(@)ANS[1,3]}}
    (( ${#ANS} > 3 )) && shown+=" +$(( ${#ANS} - 3 ))"
    cell "  ${RN[$i]}" 16; cell "$st" 11 "$col"; ms_cell "$DS_MS" 9
    cell "${shown:-(no $typ)}" 46; print
    if [[ -z "${GROUPS[$set]}" ]]; then ORDER+=("$set"); GROUPS[$set]="${RN[$i]}"; else GROUPS[$set]+=", ${RN[$i]}"; fi
  done
  print ""
  local top=${ORDER[1]} n=${#ORDER} agree=0
  local -a members
  for set in $ORDER; do
    members=(${(s:, :)GROUPS[$set]})
    (( ${#members} > agree )) && { agree=${#members}; top=$set; }
  done
  if (( n == 1 )); then
    kv "Agreement" "${C_OK}${#RIP}/${#RIP} resolvers identical${C_0}"
  else
    kv "Agreement" "${C_WARN}${agree}/${#RIP} agree on the most common answer set${C_0}"
    local cnt word
    for set in $ORDER; do
      cnt=$(print -r -- "${GROUPS[$set]}" | awk -F', ' '{print NF}')
      if (( cnt == 1 )); then word=resolver; else word=resolvers; fi
      printf "  %-14s %s\n" "$cnt $word" "${set:0:70}"
    done
  fi
  note "Propagation is not the same as cache TTL; a CDN can legitimately answer differently per region."
}

cmd_mtu() {
  local host=$1 lo=0 hi=1472 mid
  [[ -n "$host" ]] || die "usage: dns-bench mtu HOST"
  [[ "$host" =~ '^[A-Za-z0-9._:-]+$' ]] || die "invalid host"
  need ping || die "ping not found"
  section "Path MTU: $host"
  if mtu_ok "$host" "$hi"; then
    kv "Discovered MTU" "${C_OK}$(( hi + 28 ))${C_0} (no smaller path found; DF 1472 fits)"
  else
    local steps=0
    while (( hi - lo > 1 )); do
      mid=$(( (lo + hi) / 2 ))
      if mtu_ok "$host" "$mid"; then lo=$mid; else hi=$mid; fi
      (( steps++ ))
    done
    if (( lo == 0 )); then
      print "  ${C_ERR}no DF probe succeeded${C_0}: the host may block ICMP or the path is broken."
      return 1
    fi
    kv "Discovered MTU" "${C_OK}$(( lo + 28 ))${C_0} (largest DF payload that passed: $lo bytes)"
    (( TERSE )) || note "$steps bisection probes, 1500 down."
  fi
  note "MTU = payload + 28 (IPv4 + ICMP headers). A value under 1500 usually means PPPoE (1492) or a tunnel."
}

mtu_ok() {   # mtu_ok HOST PAYLOAD_BYTES -> true when the DF probe gets a reply
  local s=$2
  if (( IS_MAC )); then
    ping -c 1 -D -s "$s" -t 2 "$1" >/dev/null 2>&1
  else
    ping -c 1 -M do -s "$s" -W 2 "$1" >/dev/null 2>&1
  fi
}

cmd_ecs() {
  local host=${1:-example.com} srv=8.8.8.8 pub subnet base ecs chg=
  [[ "$host" =~ '^[A-Za-z0-9._-]+$' ]] || die "invalid host"
  section "EDNS Client Subnet: $host via $srv"
  pub=$(pub_ip)
  if [[ -n "$pub" ]]; then
    subnet="${pub%.*}.0/24"
  elif [[ -n "$LOCAL4" ]]; then
    subnet="${LOCAL4%.*}.0/24"
    note "public IP unknown; using the private subnet $subnet (resolvers may ignore RFC1918 subnets)."
  else
    print "  ${C_WARN}no address to build a subnet from${C_0}: run with -P off or check connectivity."
    return 1
  fi
  base=$(dig @$srv "$host" A +subnet=0 +short +time=4 +tries=1 2>/dev/null | sort)
  ecs=$(dig @$srv "$host" A +subnet="$subnet" +short +time=4 +tries=1 2>/dev/null | sort)
  kv "Without ECS" "${(j:, :)${(f)base}:-no answer}"
  kv "With ECS ($subnet)" "${(j:, :)${(f)ecs}:-no answer}"
  if [[ -z "$base" && -z "$ecs" ]]; then print "  ${C_ERR}no answers${C_0}: $srv unreachable or the name has no A record"; return 1; fi
  if [[ "$base" == "$ecs" ]]; then
    kv "Result" "${C_OK}ECS does not change the answer${C_0}"
  else
    kv "Result" "${C_WARN}ECS changes the answer${C_0}: this resolver is steering by client subnet (CDN/geo-DNS)"
  fi
  note "dig +subnet sends the EDNS Client Subnet option; a resolver may ignore it by policy."
}

cmd_ifaces() {
  section "Interfaces"
  print -n "${C_W}"; cell "  Interface" 13; cell "State" 10; cell "MTU" 6; cell "MAC" 19; cell "IPv4" 17; cell "IPv6" 28; cell "Media" 14; print "${C_0}"
  local name state mtu mac v4 v6 media
  if (( IS_MAC )); then
    local line
    while IFS= read -r line; do
      IFS='|' read -r name state mtu mac v4 v6 media <<< "$line"
      cell "  $name" 13
      if [[ "$state" == up ]]; then cell "$state" 10 "$C_OK"; else cell "$state" 10 "$C_D"; fi
      cell "$mtu" 6 "$C_D"; cell "$mac" 19 "$C_D"; cell "$v4" 17; cell "${v6:0:26}" 28 "$C_D"; cell "${media:0:12}" 14 "$C_D"; print
    done < <(ifconfig -a 2>/dev/null | awk '
      /^[A-Za-z0-9_.]+:/ {
        if (name != "") print name "|" state "|" mtu "|" mac "|" v4 "|" v6 "|" media;
        name=$1; sub(/:$/,"",name); state="down"; mtu="-"; mac="-"; v4="-"; v6="-"; media="-";
        if ($0 ~ /<UP/) state="up";
        for (i=1;i<=NF;i++) if ($i=="mtu") mtu=$(i+1);
        next
      }
      $1=="ether" { mac=$2 }
      $1=="inet" { v4=$2 }
      $1=="inet6" {
        a=$2; sub(/%.*/,"",a)
        if (a !~ /^fe80/) { if (v6=="-" || v6 ~ /^fe80/) v6=a }
        else if (v6=="-") v6=a
      }
      $1=="media:" { media=$0; sub(/^[ \t]*media:[ \t]*/,"",media); sub(/,.*/,"",media) }
      $1=="status:" { state=$2 }
      END { if (name != "") print name "|" state "|" mtu "|" mac "|" v4 "|" v6 "|" media }
    ')
  else
    local dev
    for dev in ${(f)"$(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | cut -d@ -f1)"}; do
      state=down; [[ "$(cat /sys/class/net/$dev/operstate 2>/dev/null)" == up ]] && state=up
      mtu=$(cat /sys/class/net/$dev/mtu 2>/dev/null); [[ -n "$mtu" ]] || mtu=-
      mac=$(cat /sys/class/net/$dev/address 2>/dev/null); [[ -n "$mac" ]] || mac=-
      v4=$(ip -4 -o addr show dev "$dev" 2>/dev/null | awk '{sub(/\/.*/,"",$4); print $4; exit}')
      v6=$(ip -6 -o addr show dev "$dev" scope global 2>/dev/null | awk '{sub(/\/.*/,"",$4); print $4; exit}')
      media=$(cat /sys/class/net/$dev/speed 2>/dev/null)
      [[ -n "$media" && "$media" != <-> ]] && media=-
      [[ "$media" == <-> ]] && media="${media} Mb/s"
      cell "  $dev" 13
      if [[ "$state" == up ]]; then cell "$state" 10 "$C_OK"; else cell "$state" 10 "$C_D"; fi
      cell "${mtu:--}" 6 "$C_D"; cell "${mac:--}" 19 "$C_D"; cell "${v4:--}" 17
      cell "${${v6:--}:0:26}" 28 "$C_D"; cell "${media:--}" 14 "$C_D"; print
    done
  fi
  note "Read from the kernel only; no DNS queries and no packets sent."
}

cmd_listen() {
  section "Listening TCP sockets"
  local out line proto localaddr port proc
  if need lsof; then
    out=$(lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null)
    if [[ -z "$out" ]]; then
      print "  ${C_WARN}no listening sockets visible${C_0}"
      note "lsof is present but returned nothing; other users' sockets need sudo."
      return 0
    fi
    print -n "${C_W}"; cell "  Proto" 9; cell "Listen address" 32; cell "Process" 28; print "${C_0}"
    local -a rows
    rows=(${(f)"$(print -r -- "$out" | awk 'NR>1 {addr=$9; sub(/ \(LISTEN\)/,"",addr); p=$8; p=(p=="IPv4"?"tcp4":"tcp6"); print p "|" addr "|" $1 "|" $2}')"})
    for line in $rows; do
      IFS='|' read -r proto localaddr proc pid <<< "$line"
      cell "  $proto" 9 "$C_D"; cell "$localaddr" 32; cell "${proc:0:20} (pid ${pid:-?})" 28 "$C_D"; print
    done
    note "Process names are only visible for your own users' sockets unless run with sudo."
  elif need netstat; then
    if (( IS_MAC )); then out=$(netstat -an -p tcp 2>/dev/null | awk '$NF=="LISTEN"')
    else out=$(netstat -ltn 2>/dev/null); fi
    if [[ -z "$out" ]]; then print "  ${C_WARN}no listening sockets visible${C_0}"; return 0; fi
    print -n "${C_W}"; cell "  Proto" 9; cell "Listen address" 32; cell "Process" 28; print "${C_0}"
    print -r -- "$out" | awk 'NR>0 {print "tcp|" $4}' | while IFS='|' read -r proto localaddr; do
      cell "  $proto" 9 "$C_D"; cell "$localaddr" 32; cell "-" 28 "$C_D"; print
    done
    note "netstat fallback cannot map ports to processes; install lsof for that."
  else
    print "  ${C_WARN}neither lsof nor netstat is installed${C_0}"
    note "Install lsof (recommended) or net-tools."
    return 1
  fi
}

cmd_wifi() {
  local dev ssid=- bssid=- chan=- band=- rssi=- noise=- tx=- sec=- phy=- src=
  detect_net
  dev=${ACTIVE_DEV:-}
  section "Wi-Fi${dev:+ ($dev)}"
  if (( IS_MAC )); then
    ssid=$(networksetup -getairportnetwork "$dev" 2>/dev/null | sed -n 's/^Current Wi-Fi Network: //p')
    [[ -z "$ssid" ]] && ssid=-
    if need airport; then
      local aout; aout=$(airport -I 2>/dev/null)
      bssid=$(print -r -- "$aout" | awk -F': ' '/ BSSID/ {print $2}')
      chan=$(print -r -- "$aout" | awk -F': ' '/ channel/ {print $2}')
      rssi=$(print -r -- "$aout" | awk -F': ' '/agrCtlRSSI/ {print $2}')
      noise=$(print -r -- "$aout" | awk -F': ' '/agrCtlNoise/ {print $2}')
      tx=$(print -r -- "$aout" | awk -F': ' '/lastTxRate/ {print $2}')
      sec=$(print -r -- "$aout" | awk -F': ' '/link auth/ {print $2}')
      src="airport"
    else
      # airport was removed in recent macOS; system_profiler is the supported path.
      local sp line
      sp=$(system_profiler SPAirPortDataType 2>/dev/null)
      src="system_profiler"
      line=$(print -r -- "$sp" | awk '
        /Current Network Information:/ {f=1; next}
        /Other Local Wi-Fi Networks:/ {f=0}
        f && /^[ ]{10,16}[^ ].*:$/ && $0 !~ /(PHY Mode|Channel|Security|Signal|Transmit Rate|Card Type|MAC Address|Locale|Country Code|Supported PHY|Supported Channels|Wake On|Status|Interfaces|Current Network)/ {
          s=$0; sub(/^[ ]+/,"",s); sub(/:$/,"",s); if (ssid=="") ssid=s; next
        }
        f && /PHY Mode:/   { p=$0; sub(/.*PHY Mode: */,"",p); phy=p }
        f && /Channel:/    { c=$0; sub(/.*Channel: */,"",c); ch=c }
        f && /Security:/   { x=$0; sub(/.*Security: */,"",x); sec=x }
        f && /Signal \/ Noise:/ { n=$0; sub(/.*Signal \/ Noise: */,"",n); sn=n }
        f && /Transmit Rate:/   { t=$0; sub(/.*Transmit Rate: */,"",t); txr=t }
        END { print ssid "|" ch "|" sn "|" txr "|" phy "|" sec }
      ')
      local spssid spchan spsn sptx spphy spsec
      IFS='|' read -r spssid spchan spsn sptx spphy spsec <<< "$line"
      [[ -n "$spssid" ]] && ssid=$spssid
      chan=${spchan%% *}; [[ -z "$chan" ]] && chan=-
      phy=${spphy:--}; tx=${sptx:--}; sec=${spsec:--}
      band=$(print -r -- "$spchan" | grep -oE '(2|5|6)GHz' | head -1)
      rssi=${spsn%%/*}; noise=${spsn##*/}
      rssi=${rssi//[^0-9-]/}; noise=${noise//[^0-9-]/}
      [[ -z "$rssi" ]] && rssi=-
      [[ -z "$noise" ]] && noise=-
    fi
    # wdutil can report BSSID but demands root; never prompt for a password here.
    if [[ "$bssid" == - || -z "$bssid" ]] && (( EUID == 0 )) && need wdutil; then
      bssid=$(wdutil info 2>/dev/null | awk -F': ' '/BSSID/ {print $2; exit}')
    fi
  else
    if need iw && [[ -n "$dev" ]]; then
      local iwout; iwout=$(iw dev "$dev" link 2>/dev/null)
      src=iw
      ssid=$(print -r -- "$iwout" | sed -n 's/^[[:space:]]*SSID: //p')
      bssid=$(print -r -- "$iwout" | sed -n 's/^[[:space:]]*Connected to //p' | awk '{print $1}')
      chan=$(print -r -- "$iwout" | sed -n 's/.*channel \([0-9]*\).*/\1/p')
      rssi=$(print -r -- "$iwout" | sed -n 's/.*signal: \(-\?[0-9]*\).*/\1/p')
      tx=$(print -r -- "$iwout" | sed -n 's/.*tx bitrate: \([0-9.]*\).*/\1/p')
      sec=$(iw dev "$dev" info 2>/dev/null | awk -F': ' '/type/ {print $2}')
    elif need nmcli; then
      src=nmcli
      local nout; nout=$(nmcli -t -f active,ssid,bssid,chan,signal,rate,security dev wifi 2>/dev/null | awk -F: '$1=="yes" {print; exit}')
      IFS=':' read -r _ ssid bssid chan rssi tx sec <<< "$nout"
    fi
  fi
  [[ -n "$chan" && "$chan" != - ]] && [[ -z "$band" ]] && band=$(print -r -- "$chan" | grep -oE '(2|5|6)GHz' | head -1)
  if [[ -z "$band" && "$chan" == <-> ]]; then
    if (( chan <= 14 )); then band=2.4GHz
    elif (( chan >= 32 && chan <= 177 )); then band=5GHz; fi
  fi
  chan=${chan%% *}
  kv "SSID" "${ssid:--}"
  kv "BSSID" "${bssid:--}"
  kv "Channel" "${chan:--}${band:+ ($band)}"
  kv "Signal / noise" "${rssi:--} dBm / ${noise:--} dBm"
  if [[ "$tx" == <-> || "$tx" == <->.<-> ]]; then kv "Tx rate" "$tx Mbps"; else kv "Tx rate" "${tx:--}"; fi
  kv "Security" "${sec:--}"
  [[ -n "$phy" && "$phy" != - ]] && kv "PHY mode" "$phy"
  (( TERSE )) || note "Source: ${src:-none}. ${src/system_profiler/system_profiler is slow (~4 s) but needs no root; airport is gone on recent macOS.}"
  if [[ "$ssid" == - || "$ssid" == *redacted* ]]; then
    note "SSID is hidden: grant Location access to the terminal, or run with sudo for wdutil. BSSID needs root on macOS."
  elif [[ "$bssid" == - ]]; then
    note "BSSID needs root on macOS (sudo wdutil info)."
  fi
  return 0
}

cmd_doctor() {
  local -i fail=0
  local b p inst sched logf=/var/log/dns-bench.log
  section "Environment"
  kv "dns-bench" "$VERSION"
  kv "Script" "$SELF"
  kv "Platform" "$(uname -s) $(uname -r) ($(uname -m))"
  kv "Shell" "zsh $ZSH_VERSION"
  if (( EUID == 0 )); then
    kv "Privileges" "${C_OK}root${C_0}"
  elif need sudo; then
    kv "Privileges" "user $(id -un), sudo available"
  else
    kv "Privileges" "${C_WARN}user $(id -un), no sudo (apply/reset will fail)${C_0}"
  fi
  kv "Working dir" "$PWD"

  section "Required tools"
  for b in dig curl perl ping awk sort; do
    if need "$b"; then printf "  %-14s %s\n" "$b" "${C_OK}ok${C_0}"
    else printf "  %-14s %s\n" "$b" "${C_ERR}MISSING${C_0}"; fail=1; fi
  done

  section "Optional tools"
  for b in openssl traceroute tracepath lsof netstat ifconfig hostname; do
    if need "$b"; then printf "  %-14s %s\n" "$b" "${C_OK}ok${C_0}"
    else printf "  %-14s %s\n" "$b" "${C_WARN}missing${C_0}"; fi
  done
  if (( IS_MAC )); then
    for b in networksetup scutil route ipconfig; do
      if need "$b"; then printf "  %-14s %s\n" "$b" "${C_OK}ok${C_0}"
      else printf "  %-14s %s\n" "$b" "${C_WARN}missing${C_0}"; fi
    done
  else
    for b in ip nmcli resolvectl iw; do
      if need "$b"; then printf "  %-14s %s\n" "$b" "${C_OK}ok${C_0}"
      else printf "  %-14s %s\n" "$b" "${C_WARN}missing${C_0}"; fi
    done
  fi

  section "Install"
  inst=$(installed_path)
  if [[ -n "$inst" ]]; then kv "Installed copy" "$inst"; else kv "Installed copy" "${C_WARN}not installed${C_0} (run: dns-bench install)"; fi

  section "Schedule"
  sched=
  if (( IS_MAC )); then
    local -a plist=(/Library/LaunchDaemons/*dns-bench*(N))
    (( ${#plist} )) && sched="launchd: ${plist[1]}"
  else
    [[ -f /etc/cron.d/dns-bench ]] && sched="/etc/cron.d/dns-bench"
    [[ -z "$sched" && -f /etc/systemd/system/dns-bench.timer ]] && sched="systemd timer"
  fi
  if need crontab; then
    p=$(crontab -l 2>/dev/null | grep 'dns-bench auto' | head -1)
    [[ -n "$p" && -z "$sched" ]] && sched="crontab: $p"
  fi
  kv "Scheduled" "${sched:-${C_D}none${C_0}}"

  section "Log"
  if [[ -r "$logf" ]]; then
    kv "File" "$logf"
    (( TERSE )) || { print "  ${C_D}last lines:${C_0}"; tail -n 5 "$logf" 2>/dev/null | sed 's/^/    /'; }
  else
    kv "File" "${C_WARN}$logf not readable${C_0} (needs root, or nothing scheduled yet)"
  fi

  section "Current DNS"
  local -a cur
  cur=(${(u)${(f)"$(sys_dns_list)"}})
  kv "In use" "${(j:, :)cur:-unknown}"

  print ""
  if (( fail )); then
    print "  ${C_ERR}doctor: a required tool is missing.${C_0}"
    if (( IS_LINUX )); then print "  Debian/Ubuntu: sudo apt install dnsutils curl openssl iproute2"; print "  Fedora/RHEL:  sudo dnf install bind-utils curl openssl iproute"; fi
    return 1
  fi
  print "  ${C_OK}doctor: all required tools present.${C_0}"
  return 0
}

# =====================================================================
# connection score
# =====================================================================
# The bands below are this tool's own rubric, written from what a healthy
# cable or fibre connection does. They are NOT a percentile against a survey
# of the internet, because no such dataset for *your* machine exists and
# inventing one would be the same class of error as the cold-cache bug.
typeset -A SCORE_V SCORE_D
typeset -A SCORE_FIX
SCORE_FIX=(
  dns       "try another resolver: dns-bench run"
  latency   "inspect the path: dns-bench trace 1.1.1.1"
  speed     "measure the link on its own: dns-bench speed"
  privacy   "find the weak link: dns-bench leak && dns-bench test example.com"
  stability "chase the loss: dns-bench wifi / dns-bench ports 1.1.1.1"
)

SCORE_ART=(
  '     ___________     '
  '     |         |     '
  '     |    @    |     '
  '     |         |     '
  '      \       /      '
  '       \_____/       '
  '         | |         '
  '         | |         '
  '      ___| |___      '
  '     |         |     '
  '     |_________|     '
)

bar() {   # bar PCT WIDTH -> ASCII bar, no newline
  local pct=${1%.*} w=${2:-20} i out=
  (( pct < 0 )) && pct=0
  (( pct > 100 )) && pct=100
  local fill=$(( pct * w / 100 ))
  for (( i = 1; i <= w; i++ )); do
    if (( i <= fill )); then out+="#"; else out+="."; fi
  done
  print -n -- "$out"
}

score_colour() {   # score_colour PCT -> colour escape for that level
  local p=${1%.*}
  if   (( p >= 85 )); then print -n -- "$C_OK"
  elif (( p >= 70 )); then print -n -- "$C_C"
  elif (( p >= 55 )); then print -n -- "$C_WARN"
  else print -n -- "$C_ERR"; fi
}

score_band_name() {   # score_band_name TOTAL
  local t=${1%.*}
  if   (( t >= 93 )); then print "top tier"
  elif (( t >= 85 )); then print "strong"
  elif (( t >= 72 )); then print "above typical"
  elif (( t >= 58 )); then print "typical"
  elif (( t >= 42 )); then print "below typical"
  else print "weak"; fi
}

score_grade() {   # score_grade TOTAL -> single letter
  local t=${1%.*}
  if   (( t >= 93 )); then print S
  elif (( t >= 85 )); then print A
  elif (( t >= 72 )); then print B
  elif (( t >= 58 )); then print C
  elif (( t >= 42 )); then print D
  else print E; fi
}

# score_compute KEY=VAL ... -> "dns=NN.N" lines; -1 means "not measurable"
score_compute() {
  printf '%s\n' "$@" | awk -F= '
    function band(x, list,   n, p, i, kv, px, ps, cx, cs) {
      if (x < 0) return -1
      n = split(list, p, ",")
      split(p[1], kv, ":"); px = kv[1] + 0; ps = kv[2] + 0
      if (x <= px) return ps
      for (i = 2; i <= n; i++) {
        split(p[i], kv, ":"); cx = kv[1] + 0; cs = kv[2] + 0
        if (x <= cx) return ps + (cs - ps) * (x - px) / (cx - px)
        px = cx; ps = cs
      }
      return ps
    }
    function mix(s1, w1, s2, w2, s3, w3, s4, w4,   sum, w) {
      sum = 0; w = 0
      if (s1 >= 0) { sum += s1 * w1; w += w1 }
      if (s2 >= 0) { sum += s2 * w2; w += w2 }
      if (s3 >= 0) { sum += s3 * w3; w += w3 }
      if (s4 >= 0) { sum += s4 * w4; w += w4 }
      return (w > 0) ? sum / w : -1
    }
    { v[$1] = $2 + 0 }
    END {
      cached_s = band(v["cached"], "5:100,10:92,20:82,40:66,80:46,150:26,300:8")
      cold_s   = band(v["cold"],   "20:100,50:86,100:66,200:42,400:20,800:6")
      djit_s   = band(v["djit"],   "1:100,5:86,15:62,30:38,60:16")
      dloss_s  = band(v["dloss"],  "0:100,1:88,3:62,6:38,12:14,25:0")
      icmp_s   = band(v["icmp"],   "5:100,15:94,30:84,60:66,120:42,250:18")
      ijit_s   = band(v["ijit"],   "2:100,8:84,20:60,40:34")
      iloss_s  = band(v["iloss"],  "0:100,2:66,5:34,10:10")
      down_s   = band(v["down"],   "2:6,5:16,10:30,25:52,50:68,100:80,250:92,500:100")
      up_s     = band(v["up"],     "1:6,5:30,10:50,25:70,50:86,100:100")

      nx_s     = (v["nx"]     < 0) ? 50 : v["nx"]
      dnssec_s = (v["dnssec"] < 0) ? 50 : v["dnssec"]
      egress_s = (v["egress"] < 0) ? 50 : v["egress"]
      dot_s    = (v["dot"]    < 0) ? 50 : v["dot"]

      dns  = mix(cached_s, 0.50, cold_s, 0.30, djit_s, 0.10, dloss_s, 0.10)
      net  = mix(icmp_s,   0.70, ijit_s, 0.20, iloss_s, 0.10, -1, 0)
      spd  = mix(down_s,   0.65, up_s,   0.35, -1, 0, -1, 0)
      priv = mix(nx_s,     0.30, dnssec_s, 0.25, egress_s, 0.25, dot_s, 0.20)
      stab = mix(dloss_s,  0.50, iloss_s, 0.50, -1, 0, -1, 0)

      w = 0; t = 0
      if (dns  >= 0) { t += dns  * 0.35; w += 0.35 }
      if (net  >= 0) { t += net  * 0.20; w += 0.20 }
      if (spd  >= 0) { t += spd  * 0.20; w += 0.20 }
      if (priv >= 0) { t += priv * 0.15; w += 0.15 }
      if (stab >= 0) { t += stab * 0.10; w += 0.10 }
      total = (w > 0) ? t / w : 0

      printf "dns=%.1f\n",       dns
      printf "latency=%.1f\n",   net
      printf "speed=%.1f\n",     spd
      printf "privacy=%.1f\n",   priv
      printf "stability=%.1f\n", stab
      printf "total=%.1f\n",     total
    }
  '
}

score_render() {   # score_render [--animate]   (reads SCORE_V and SCORE_D)
  local anim=${1:-} m pct col b total grade band pos
  local -a metrics=(dns latency speed privacy stability)
  total=${SCORE_V[total]:-0}
  grade=$(score_grade "$total")
  band=$(score_band_name "$total")

  print ""
  for m in $metrics; do
    [[ "${SCORE_V[$m]:--1}" == -* ]] && continue
    pct=${SCORE_V[$m]%.*}
    col=$(score_colour "$pct")
    b=$(bar "$pct" 20)
    printf "  %-10s %s%s%s  ${C_B}%3d${C_0}   %s\n" "$m" "$col" "$b" "$C_0" "$pct" "${C_D}${SCORE_D[$m]}${C_0}"
    [[ "$anim" == --animate ]] && sleep 0.05
  done

  pct=${total%.*}
  col=$(score_colour "$pct")
  print ""
  if [[ "$anim" == --animate ]]; then
    local step
    for (( step = 1; step <= 20; step++ )); do
      printf "\r  %-10s %s%s%s  %3d  " "total" "$col" "$(bar $(( pct * step / 20 )) 20)" "$C_0" $(( pct * step / 20 ))
      sleep 0.025
    done
  fi
  local cr=
  [[ "$anim" == --animate ]] && cr=$'\r'
  printf "%s  %-10s %s%s%s  ${C_B}%3d${C_0}   %s\n" "$cr" "total" "$col" "$(bar "$pct" 20)" "$C_0" "$pct" "${C_W}${band}${C_0}"

  if (( pct >= 72 )); then
    print ""
    [[ "$anim" == --animate ]] && sleep 0.12
    local line art
    for line in "${SCORE_ART[@]}"; do
      art=${line//@/$grade}
      print -r -- "  ${col}${art%% ##}${C_0}"
      [[ "$anim" == --animate ]] && sleep 0.045
    done
  else
    local -a pairs
    local pm
    for pm in $metrics; do
      [[ "${SCORE_V[$pm]:--1}" == -* ]] && continue
      pairs+=("${SCORE_V[$pm]%.*} $pm")
    done
    pairs=(${(on)pairs})
    print ""
    note "no trophy this run, but the weakest lines are specific:"
    local rank=0
    for pm in "${pairs[@]}"; do
      (( ++rank > 2 )) && break
      pm=${pm#* }
      print "  ${C_WARN}-${C_0} $pm ${C_D}(${SCORE_V[$pm]%.*}%)${C_0}: ${SCORE_FIX[$pm]}"
    done
  fi

  print ""
  print "  ${C_B}${grade}${C_0}   ${total}/100   ${C_D}${band}${C_0}"
  print ""
  pos=$(( (pct * 51 + 50) / 100 ))
  print "  ${C_D}0        20        40        60        80        100${C_0}"
  print "  ${C_D}|--------|---------|---------|---------|---------|${C_0}"
  printf "  %s%s^ %s %s\n" "$(printf '%*s' "$pos" '')" "$col" "$total" "$band"
}

cmd_score() {
  local cur pub egress nx ds dot cstats kstats idx= lat jit loss dl ul dln upn
  local -i anim=0
  detect_net
  [[ -n "$ACTIVE_DEV" ]] || die "no default route: you appear to be offline"
  need dig || die "dig is required"
  build_resolvers
  cur=${SYS_DNS[1]:-$GATEWAY}
  [[ -n "$cur" ]] || die "no resolver configured: nothing to score"
  (( PROGRESS_TTY && ! TERSE )) && anim=1

  idx=$(resolver_of_ip "$cur" 2>/dev/null)
  print "${C_B}dns-bench $VERSION${C_0}  ${C_D}connection score${C_0}"
  kv "Resolver" "$cur${idx:+ (#$idx)}"
  kv "Target" "$DOMAIN, $SAMPLES samples"
  local est=$(( SPEED_SECS + 10 ))
  (( SPEED_UPLOAD )) && est=$(( SPEED_SECS * 2 + 10 ))
  kv "Measured" "dns, latency, throughput, privacy (about ${est}s)"
  if (( TUNNEL )); then
    kv "VPN" "${C_C}tunnel $DEF_DEV${C_0}: DNS is scored through the tunnel, not around it"
  else
    kv "VPN" "none detected"
  fi

  cstats=$(dns_stats "$cur" cached "$SAMPLES")
  [[ -n "$idx" ]] || idx=0
  kstats=$(dns_stats "$cur" cold 3 "$idx")

  read -r lat jit loss <<< "$(ping_detail 1.1.1.1)"
  if [[ "$lat" == Timeout ]]; then read -r lat jit loss <<< "$(ping_detail 8.8.8.8)"; fi

  dl=$(speed_download "$SPEED_SECS")
  (( PROGRESS_TTY )) && print
  if (( SPEED_UPLOAD )); then ul=$(speed_upload "$SPEED_SECS"); else ul=fail; fi

  nx=$(t_nx "$cur" "$idx")
  ds=$(t_dnssec "$cur")
  dot=$(t_port "$cur" 853)
  pub=; egress=
  if (( ! NO_EXT )); then
    pub=$(pub_ip)
    egress=$(dig +short whoami.akamai.net +time=3 +tries=1 2>/dev/null | tail -1)
  fi

  local -a kvargs
  local c_med d_jit d_loss k_med
  c_med=${${=cstats}[1]}; d_jit=; d_loss=${${=cstats}[4]}
  if is_num "${${=cstats}[2]}" && is_num "${${=cstats}[3]}"; then
    d_jit=$(printf '%.1f' $(( ${${=cstats}[3]} - ${${=cstats}[2]} )))
  fi
  k_med=${${=kstats}[1]}
  is_num "$c_med" || c_med=-1
  is_num "$k_med" || k_med=-1
  is_num "$d_jit" || d_jit=-1
  is_num "$d_loss" || d_loss=-1

  [[ "$lat" == Timeout ]] && lat=-1
  is_num "$lat" || lat=-1
  is_num "$jit" || jit=-1
  is_num "$loss" || loss=-1

  dln=${dl%% *}; upn=${ul%% *}
  if [[ "$dl" == fail* ]] || ! is_num "$dln"; then dln=-1; fi
  if [[ "$ul" == fail* ]] || ! is_num "$upn"; then upn=-1; fi

  kvargs=("cached=$c_med" "cold=$k_med" "djit=$d_jit" "dloss=$d_loss"
          "icmp=$lat" "ijit=$jit" "iloss=$loss" "down=$dln" "up=$upn")
  case "$nx" in ok) kvargs+=("nx=100") ;; HIJACK) kvargs+=("nx=0") ;; *) kvargs+=("nx=-1") ;; esac
  case "$ds" in yes) kvargs+=("dnssec=100") ;; no) kvargs+=("dnssec=25") ;; *) kvargs+=("dnssec=-1") ;; esac
  case "$dot" in yes) kvargs+=("dot=100") ;; *) kvargs+=("dot=40") ;; esac
  if (( NO_EXT )) || [[ -z "$pub" || -z "$egress" ]]; then kvargs+=("egress=-1")
  elif [[ "$pub" == "$egress" ]]; then kvargs+=("egress=100")
  else kvargs+=("egress=30"); fi

  local k v
  while IFS='=' read -r k v; do [[ -n "$k" ]] && SCORE_V[$k]=$v; done < <(score_compute "${kvargs[@]}")

  SCORE_D[dns]="cached ${c_med/-1/?} ms, cold ${k_med/-1/?} ms, ${d_loss/-1/?}% loss"
  SCORE_D[latency]="${lat/-1/?} ms, jitter ${jit/-1/?} ms"
  if (( ! SPEED_UPLOAD )); then
    SCORE_D[speed]="down ${dln/-1/?} Mbps, upload skipped"
  else
    SCORE_D[speed]="down ${dln/-1/?} Mbps, up ${upn/-1/?} Mbps"
  fi
  SCORE_D[privacy]="NXDOMAIN $nx, DNSSEC $ds, DoT $dot"
  local l1=${d_loss/-1/?} l2=${loss/-1/?}
  l1=${l1%.0}; l2=${l2%.0}
  SCORE_D[stability]="${l1}% DNS loss, ${l2}% ICMP loss"

  (( anim )) && score_render --animate || score_render

  print ""
  (( TUNNEL )) && note "VPN detected: the privacy line scores the resolver you reach through $DEF_DEV. A leak shows up as a mismatch, not as a lower score by itself."
  (( NO_EXT )) && note "Privacy mode: external IP checks were skipped, so the egress item is neutral."
  [[ "$dl" == fail* ]] && note "Throughput unavailable, so the speed line was left out of the total and the rest was reweighted."
  note "Bands are this tool's rubric for a healthy connection, not a survey of the internet. Run twice before reading a 3-point difference."
}

# =====================================================================
# dispatch
# =====================================================================
case "$CMD" in
  run)       cmd_run ;;
  info)      cmd_info ;;
  test)      cmd_test "$1" ;;
  best)      cmd_best ;;
  adblock)   cmd_adblock "$1" ;;
  set)       cmd_set "$1" ;;
  reset)     cmd_reset ;;
  flush)     cmd_flush ;;
  status)    cmd_status ;;
  list)      cmd_list ;;
  speed)     cmd_speed ;;
  demo)      cmd_demo ;;
  auto)      cmd_auto ;;
  install)   cmd_install ;;
  uninstall) cmd_uninstall ;;
  cron)      cmd_cron "$1" ;;
  update)    cmd_update "$@" ;;
  ports)     cmd_ports "$1" "$2" ;;
  http)      cmd_http "$1" ;;
  tls)       cmd_tls "$1" ;;
  trace)     cmd_trace "$1" ;;
  asn)       cmd_asn "$1" ;;
  ptr)       cmd_ptr "$1" ;;
  leak)      cmd_leak ;;
  propagation) cmd_propagation "$1" "$2" ;;
  mtu)       cmd_mtu "$1" ;;
  ecs)       cmd_ecs "$1" ;;
  ifaces)    cmd_ifaces ;;
  listen)    cmd_listen ;;
  wifi)      cmd_wifi ;;
  doctor)    cmd_doctor ;;
  score)     cmd_score ;;
esac
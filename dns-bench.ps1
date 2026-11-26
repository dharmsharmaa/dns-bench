#Requires -Version 5.1
<#
  dns-bench 3.3 for Windows
  Benchmark public DNS resolvers, inspect your network, troubleshoot domains,
  and switch DNS on your active adapter.

  Author:  Dharm Sharma (https://dharmsharma.com)
  License: MIT (see LICENSE)
  Docs:    readme.md

  Works with Windows PowerShell 5.1 and PowerShell 7+.
  Run:     powershell -ExecutionPolicy Bypass -File .\dns-bench.ps1 help
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)][string]$Command = 'run',
  [Parameter(Position = 1)][string]$Argument,
  [string]$Domain = 'google.com',
  [ValidateRange(1, 20)][int]$Samples = 5,
  [ValidateRange(1, 12)][int]$TopK = 5,
  [string]$ExtraServices,
  [string]$Csv,
  [switch]$NoCsv,
  [switch]$SkipServices,
  [switch]$SkipGeo,
  [switch]$Quick,
  [switch]$Privacy,
  [switch]$ReportOnly,
  [switch]$Yes,
  [switch]$NoProgress,
  [switch]$Check,
  [switch]$Force,
  [ValidateRange(2, 60)][int]$Duration = 10,
  [switch]$NoUpload,
  [switch]$Q,
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = if ($NoProgress) { 'SilentlyContinue' } else { 'Continue' }

$script:Version = '3.3.0'
$script:SelfPath = $PSCommandPath
if (-not $script:SelfPath) { $script:SelfPath = $MyInvocation.MyCommand.Path }
$script:SelfDir = Split-Path -Parent $script:SelfPath
$script:OnWindows = ($env:OS -eq 'Windows_NT')

$script:OSKind = 'windows'
if (-not $script:OnWindows) {
  $script:OSKind = 'linux'
  try {
    $unameOut = (& uname -s 2>$null)
    if ($unameOut -eq 'Darwin') { $script:OSKind = 'macos' }
  } catch { }
}

# Base36 helper and one salt per run. Cold names embed the run salt, the
# resolver index and the sample index, so no two probes in the same run and
# no two runs ever ask for the same "cold" name. Without that, a name warmed
# by one resolver can be answered from cache by another (Verisign and
# Neustar share the UltraDNS backend), which silently turns a cold
# measurement into a cache hit and makes the score incomparable.
function ConvertTo-Base36([int64]$Value) {
  $digits = '0123456789abcdefghijklmnopqrstuvwxyz'
  if ($Value -le 0) { return '0' }
  $text = ''
  while ($Value -gt 0) {
    $text = $digits[[int]($Value % 36)] + $text
    $Value = [int64][math]::Floor($Value / 36)
  }
  return $text
}

function Get-RunSalt {
  $epoch = [int64](([DateTime]::UtcNow - [datetime]'1970-01-01').TotalMilliseconds)
  $value = $epoch * 1000 + (Get-Random -Minimum 0 -Maximum 1000)
  $text = ConvertTo-Base36 $value
  if ($text.Length -gt 6) { $text = $text.Substring($text.Length - 6) }
  return $text
}

$script:RunSalt = Get-RunSalt

# Unique names are what make the cold number comparable across resolvers:
# a name warmed by any earlier probe cannot be answered from cache here.
function New-ColdName {
  param([int]$ResolverIndex, [int]$SampleIndex)
  $tlds = @('com', 'net', 'org')
  $tld = $tlds[(Get-Random -Maximum 3)]
  $name = 'cold-{0}-r{1}-{2}.{3}' -f $script:RunSalt, $ResolverIndex, $SampleIndex, $tld
  if ($env:DNSBENCH_DEBUG_COLD) { [Console]::Error.WriteLine("cold name: $name") }
  return $name
}

function New-NxProbeName {
  param([int]$ResolverIndex)
  $name = 'nx-{0}-r{1}.com' -f $script:RunSalt, $ResolverIndex
  if ($env:DNSBENCH_DEBUG_COLD) { [Console]::Error.WriteLine("nx name: $name") }
  return $name
}

# Where `update` pulls the latest version from.
# Override per run with:  $env:DNSBENCH_UPDATE_URL = 'https://...'
$script:UpdateUrl = if ($env:DNSBENCH_UPDATE_URL) {
  $env:DNSBENCH_UPDATE_URL
} else {
  'https://raw.githubusercontent.com/dharmsharmaa/dns-bench/main/dns-bench.ps1'
}

$script:TmpDir = Join-Path ([IO.Path]::GetTempPath()) ('dns-bench-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $script:TmpDir -Force | Out-Null

$script:IsAdmin = $false
if ($script:OnWindows) {
  try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $script:IsAdmin = (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole(
      [Security.Principal.WindowsBuiltInRole]::Administrator)
  } catch { }
}

if ($Quick) {
  $SkipServices = $true
  $SkipGeo = $true
  $Samples = 3
  if (-not $PSBoundParameters.ContainsKey('Duration')) { $Duration = 4 }
}

# =====================================================================
# output helpers
# =====================================================================
function Write-Section([string]$Text) {
  Write-Host ''
  Write-Host "== $Text ==" -ForegroundColor Cyan
}

function Write-Kv([string]$Key, [string]$Value) {
  Write-Host ('  {0,-26} {1}' -f $Key, $Value)
}

function Write-Note([string]$Text) {
  Write-Host "  $Text" -ForegroundColor DarkGray
}

function Write-Bad([string]$Text) {
  Write-Host $Text -ForegroundColor Red
}

function Write-Good([string]$Text) {
  Write-Host $Text -ForegroundColor Green
}

function Write-Warn2([string]$Text) {
  Write-Host "  warning: $Text" -ForegroundColor Yellow
}

function Show-Usage {
  @'
dns-bench (Windows / PowerShell): benchmark DNS resolvers, check your network,
troubleshoot domains.

Usage: .\dns-bench.ps1 <command> [args] [options]
       .\dns-bench.ps1 help <command>

Benchmark
  run                 full benchmark + tables, then asks what to apply (default)
  best                quick benchmark, apply the fastest unfiltered resolver

DNS control
  set NAME|#          apply a resolver without benchmarking (set cloudflare)
  reset               back to automatic dns (DHCP / router)
  adblock [off]       apply the fastest ad-blocking resolver (off = automatic dns)
  status              what dns you use now, script location
  list                print the resolver list
  flush               flush the DNS cache

Diagnose
  test DOMAIN         troubleshoot a domain: compare resolvers, records,
                      DNSSEC, TCP/HTTPS reachability
  info                network info only (ips, gateway, dns in use, geo)

Network
  speed               network speed test: latency, jitter, download, upload
  ports HOST [PORTS]  TCP connect check, default ports 22 53 80 443 853 3306
                      5432 6379 8080 (comma or space separated)
  http URL            HTTP code + timing: dns, connect, tls, ttfb, total
  tls HOST[:PORT]     certificate subject CN, issuer, dates, days left, SANs
  trace HOST          traceroute, numeric, 16 hops
  asn HOST|IP         ASN, prefix, country, registry, org
  ptr IP              PTR records + forward-confirmed reverse DNS
  leak                resolver egress vs your public IP
  propagation DOMAIN [TYPE]  compare the answer across 8 public resolvers
  mtu HOST            path MTU by DF ping bisection
  ecs [HOST]          does EDNS Client Subnet change the answer?
  ifaces              interfaces: state, MTU, MAC, IPv4, IPv6, media
  listen              listening TCP sockets and their processes
  wifi                SSID, BSSID, channel, band, signal, rate, security

Maintenance
  update              pull the latest version of this script from GitHub
  demo                print sample output for screenshots (no network, no changes)
  doctor              dependency checklist; exits 1 if something required is missing
  version, help

Options
  -Domain NAME     domain for the cached-latency test (default google.com)
  -Samples N       samples per resolver, 1-20 (default 5)
  -TopK K          resolvers in the service test, 1-12 (default 5)
  -ExtraServices   extra hostnames for the service test, comma separated
  -Csv FILE        save results as CSV to FILE
  -NoCsv           don't auto-save a CSV next to the script
  -NoProgress      no progress bar
  -SkipServices    skip the popular-service test
  -SkipGeo         skip the continent latency test
  -Quick           -SkipServices -SkipGeo, 3 samples, speed phases 4 s
  -Q               terse output for the network commands (alias: -q)
  -Privacy         no external ip/geo lookups
  -ReportOnly      never change DNS
  -Yes             don't ask, apply the best resolver
  -Check           (update) only report whether a newer version exists
  -Force           (update) reinstall even if the version matches
  -Duration SECS   (speed) seconds per phase, 2-60 (default 10, -Quick uses 4)
  -NoUpload        (speed) skip the upload test

Examples
  .\dns-bench.ps1
  .\dns-bench.ps1 -Quick -ReportOnly
  .\dns-bench.ps1 test github.com
  .\dns-bench.ps1 set cloudflare
  .\dns-bench.ps1 help ports

Env: DNSBENCH_UPDATE_URL   override the GitHub raw URL used by update
     DNSBENCH_CSV_DIR      where auto-saved CSVs go (default: next to the script)
     DNSBENCH_DEBUG_COLD=1 print generated cold/NX names to stderr
'@ | Write-Host
}

# Per-command help: usage, one paragraph, two examples. Keep names/flags the
# same as dns-bench.zsh so a command reads the same on either platform.
$script:CommandHelp = @{
  'run' = @{
    Usage = 'run [options]'
    Summary = 'Full benchmark: network info, cached/cold/jitter/loss, feature matrix, continents, popular services, then offers to apply a resolver.'
    Examples = @('.\dns-bench.ps1', '.\dns-bench.ps1 run -Quick -ReportOnly -Samples 3')
  }
  'best' = @{
    Usage = 'best'
    Summary = 'Quick benchmark of the unfiltered resolvers and apply the fastest one (asks unless -Yes).'
    Examples = @('.\dns-bench.ps1 best', '.\dns-bench.ps1 best -ReportOnly')
  }
  'set' = @{
    Usage = 'set NAME|#'
    Summary = 'Apply a resolver by name fragment or by its # in the list, without benchmarking.'
    Examples = @('.\dns-bench.ps1 set cloudflare', '.\dns-bench.ps1 set 4')
  }
  'reset' = @{
    Usage = 'reset'
    Summary = 'Put DNS back to automatic (DHCP/router) on the active adapter and flush the cache.'
    Examples = @('.\dns-bench.ps1 reset', '.\dns-bench.ps1 reset')
  }
  'adblock' = @{
    Usage = 'adblock [off]'
    Summary = 'Benchmark ad-blocking resolvers, verify they really block, apply the fastest. "off" returns to automatic DNS.'
    Examples = @('.\dns-bench.ps1 adblock', '.\dns-bench.ps1 adblock off')
  }
  'status' = @{
    Usage = 'status'
    Summary = 'Show the adapter, DNS source, DNS in use, script path and update URL.'
    Examples = @('.\dns-bench.ps1 status', '.\dns-bench.ps1 status')
  }
  'list' = @{
    Usage = 'list'
    Summary = 'Print every resolver with its #, kind, region and addresses.'
    Examples = @('.\dns-bench.ps1 list', '.\dns-bench.ps1 list')
  }
  'flush' = @{
    Usage = 'flush'
    Summary = 'Flush the Windows DNS cache (Clear-DnsClientCache + ipconfig /flushdns).'
    Examples = @('.\dns-bench.ps1 flush', '.\dns-bench.ps1 flush')
  }
  'test' = @{
    Usage = 'test DOMAIN'
    Summary = 'Troubleshoot a domain: same query through several resolvers, records, DNSSEC, TCP/HTTPS reachability and a verdict.'
    Examples = @('.\dns-bench.ps1 test github.com', '.\dns-bench.ps1 test example.org')
  }
  'info' = @{
    Usage = 'info'
    Summary = 'Network info only: adapter, addresses, gateway, DNS in use, public IP, geo, VPN/proxy.'
    Examples = @('.\dns-bench.ps1 info', '.\dns-bench.ps1 info -Privacy')
  }
  'speed' = @{
    Usage = 'speed [-Duration SECS] [-NoUpload]'
    Summary = 'Latency/jitter plus parallel download and upload throughput against the Cloudflare edge (OVH fallback).'
    Examples = @('.\dns-bench.ps1 speed', '.\dns-bench.ps1 speed -Duration 5 -NoUpload')
  }
  'ports' = @{
    Usage = 'ports HOST [PORTS]'
    Summary = 'TCP connect check. State is open, closed (refused) or filtered (no answer in 2 s). PORTS defaults to 22 53 80 443 853 3306 5432 6379 8080; comma or space separated.'
    Examples = @('.\dns-bench.ps1 ports example.com', '.\dns-bench.ps1 ports 1.1.1.1 53,443,853')
  }
  'http' = @{
    Usage = 'http URL'
    Summary = 'HTTP status plus timing breakdown in ms: dns, connect, tls, ttfb, total; also size, redirects and final URL. Uses curl.'
    Examples = @('.\dns-bench.ps1 http https://example.com', '.\dns-bench.ps1 http github.com')
  }
  'tls' = @{
    Usage = 'tls HOST[:PORT]'
    Summary = 'Certificate chain endpoint check: subject CN, issuer, notBefore, notAfter, days left, SAN count, protocol. Warns under 21 days. Prefers openssl s_client, falls back to curl -v.'
    Examples = @('.\dns-bench.ps1 tls example.com', '.\dns-bench.ps1 tls 1.1.1.1:443')
  }
  'trace' = @{
    Usage = 'trace HOST'
    Summary = 'Path trace, numeric, 16 hops, one probe per hop (traceroute, tracepath, or tracert on Windows).'
    Examples = @('.\dns-bench.ps1 trace 1.1.1.1', '.\dns-bench.ps1 trace example.com')
  }
  'asn' = @{
    Usage = 'asn HOST|IP'
    Summary = 'ASN, prefix, country, registry and org for an address, via the Team Cymru DNS service (no whois binary).'
    Examples = @('.\dns-bench.ps1 asn 8.8.8.8', '.\dns-bench.ps1 asn github.com')
  }
  'ptr' = @{
    Usage = 'ptr IP'
    Summary = 'PTR records for an IPv4/IPv6 address plus forward-confirmed reverse DNS (yes/no).'
    Examples = @('.\dns-bench.ps1 ptr 8.8.8.8', '.\dns-bench.ps1 ptr 1.1.1.1')
  }
  'leak' = @{
    Usage = 'leak'
    Summary = 'Compare your public IP with the egress IP the system resolver and each configured resolver actually query from; flags a mismatch.'
    Examples = @('.\dns-bench.ps1 leak', '.\dns-bench.ps1 leak -Privacy')
  }
  'propagation' = @{
    Usage = 'propagation DOMAIN [TYPE]'
    Summary = 'Ask 8 public resolvers for the same record, group identical answer sets and print an agreement summary. TYPE defaults to A.'
    Examples = @('.\dns-bench.ps1 propagation example.com', '.\dns-bench.ps1 propagation example.com AAAA')
  }
  'mtu' = @{
    Usage = 'mtu HOST'
    Summary = 'Discover the path MTU with a don''t-fragment ping bisection from 1500 bytes down.'
    Examples = @('.\dns-bench.ps1 mtu 1.1.1.1', '.\dns-bench.ps1 mtu example.com')
  }
  'ecs' = @{
    Usage = 'ecs [HOST]'
    Summary = 'EDNS Client Subnet check: compare +subnet=0 with +subnet=<your public ip>/24 on 8.8.8.8 and report whether ECS changes the answer. Needs dig.'
    Examples = @('.\dns-bench.ps1 ecs', '.\dns-bench.ps1 ecs example.com')
  }
  'ifaces' = @{
    Usage = 'ifaces'
    Summary = 'Interface inventory: state, MTU, MAC, IPv4, IPv6 and media. No DNS queries, works offline.'
    Examples = @('.\dns-bench.ps1 ifaces', '.\dns-bench.ps1 ifaces -Q')
  }
  'listen' = @{
    Usage = 'listen'
    Summary = 'Listening TCP sockets: protocol, local address:port and owning process. Get-NetTCPConnection on Windows, lsof or netstat elsewhere.'
    Examples = @('.\dns-bench.ps1 listen', '.\dns-bench.ps1 listen -Q')
  }
  'wifi' = @{
    Usage = 'wifi'
    Summary = 'Wireless link detail: SSID, BSSID, channel, band, RSSI/signal, noise, tx rate and security.'
    Examples = @('.\dns-bench.ps1 wifi', '.\dns-bench.ps1 wifi -Q')
  }
  'doctor' = @{
    Usage = 'doctor'
    Summary = 'Dependency and install checklist: every tool it uses, privilege status, installed copy, schedule, log tail and version. Exits 1 if a required dependency is missing. Works offline.'
    Examples = @('.\dns-bench.ps1 doctor', '.\dns-bench.ps1 doctor')
  }
  'demo' = @{
    Usage = 'demo'
    Summary = 'Print sample output for screenshots. No network, no changes.'
    Examples = @('.\dns-bench.ps1 demo', '.\dns-bench.ps1 demo -SkipServices')
  }
  'update' = @{
    Usage = 'update [-Check] [-Force]'
    Summary = 'Download the latest script from DNSBENCH_UPDATE_URL, back up the current copy and replace it.'
    Examples = @('.\dns-bench.ps1 update', '.\dns-bench.ps1 update -Check')
  }
  'help' = @{
    Usage = 'help [command]'
    Summary = 'Show the grouped command list, or detailed usage and examples for one command.'
    Examples = @('.\dns-bench.ps1 help', '.\dns-bench.ps1 help ports')
  }
  'version' = @{
    Usage = 'version'
    Summary = 'Print the script version.'
    Examples = @('.\dns-bench.ps1 version', '.\dns-bench.ps1 version')
  }
}

$script:AllCommands = @(
  'run', 'best', 'set', 'reset', 'adblock', 'status', 'list', 'flush',
  'test', 'info', 'speed',
  'ports', 'http', 'tls', 'trace', 'asn', 'ptr', 'leak', 'propagation', 'mtu', 'ecs', 'ifaces', 'listen', 'wifi',
  'update', 'demo', 'doctor', 'help', 'version'
)

function Get-TextDistance([string]$A, [string]$B) {
  $a = $A.ToLower()
  $b = $B.ToLower()
  $rows = $a.Length + 1
  $cols = $b.Length + 1
  $grid = New-Object 'int[,]' $rows, $cols
  for ($i = 0; $i -lt $rows; $i++) { $grid[$i, 0] = $i }
  for ($j = 0; $j -lt $cols; $j++) { $grid[0, $j] = $j }
  for ($i = 1; $i -lt $rows; $i++) {
    for ($j = 1; $j -lt $cols; $j++) {
      $cost = 1
      if ($a[$i - 1] -eq $b[$j - 1]) { $cost = 0 }
      $delete = $grid[($i - 1), $j] + 1
      $insert = $grid[$i, ($j - 1)] + 1
      $replace = $grid[($i - 1), ($j - 1)] + $cost
      $grid[$i, $j] = [math]::Min($delete, [math]::Min($insert, $replace))
    }
  }
  return $grid[($rows - 1), ($cols - 1)]
}

function Get-ClosestCommand([string]$Name) {
  if (-not $Name) { return $null }
  $wanted = $Name.ToLower()
  foreach ($candidate in $script:AllCommands) {
    if ($candidate -eq $wanted) { return $candidate }
  }
  foreach ($candidate in $script:AllCommands) {
    if ($candidate.StartsWith($wanted) -or $wanted.StartsWith($candidate)) { return $candidate }
  }
  foreach ($candidate in $script:AllCommands) {
    if ($candidate.Contains($wanted) -or $wanted.Contains($candidate)) { return $candidate }
  }
  $best = $null
  $bestDistance = 99
  foreach ($candidate in $script:AllCommands) {
    $distance = Get-TextDistance $wanted $candidate
    if ($distance -lt $bestDistance) { $bestDistance = $distance; $best = $candidate }
  }
  if ($bestDistance -le 2) { return $best }
  return $null
}

function Show-CommandHelp([string]$Name) {
  if (-not $Name) { Show-Usage; return 0 }
  $key = $Name.ToLower().TrimStart('-')
  if (-not $script:CommandHelp.ContainsKey($key)) {
    Write-Bad "no such command: $Name"
    $suggestion = Get-ClosestCommand $key
    if ($suggestion) { Write-Host "Did you mean: ${suggestion}? Try: .\dns-bench.ps1 help $suggestion" }
    else { Write-Host 'Run: .\dns-bench.ps1 help' }
    return 1
  }
  $entry = $script:CommandHelp[$key]
  Write-Host ''
  Write-Host ("dns-bench {0}" -f $entry.Usage) -ForegroundColor White
  Write-Host ''
  Write-Host ("  {0}" -f $entry.Summary)
  Write-Host ''
  Write-Host 'Examples' -ForegroundColor Cyan
  foreach ($example in $entry.Examples) { Write-Host ("  {0}" -f $example) }
  Write-Host ''
  Write-Host ("More: .\dns-bench.ps1 help    |    version {0}" -f $script:Version) -ForegroundColor DarkGray
  return 0
}

# =====================================================================
# resolver list
# =====================================================================
# Kind: U unfiltered | F filters/blocks content | A blocks ads/trackers | C current/local
# Region: GL global anycast, NA, SA, EU, AS, OC, AF, LAN
$script:RegionNames = @{
  GL = 'Global anycast'; NA = 'North America'; SA = 'South America'; EU = 'Europe'
  AS = 'Asia'; OC = 'Oceania'; AF = 'Africa'; LAN = 'Local network'
}

function New-Resolver([string]$Name, [string]$Kind, [string]$Region, [string[]]$V4, [string[]]$V6) {
  [pscustomobject]@{
    Name = $Name; Kind = $Kind; Region = $Region
    V4 = @($V4 | Where-Object { $_ -and $_ -ne 'none' })
    V6 = @($V6 | Where-Object { $_ -and $_ -ne 'none' })
  }
}

$script:Resolvers = @(
  New-Resolver 'Cloudflare' 'U' 'GL' @('1.1.1.1', '1.0.0.1') @('2606:4700:4700::1111', '2606:4700:4700::1001')
  New-Resolver 'Cloudflare Malware' 'F' 'GL' @('1.1.1.2', '1.0.0.2') @('2606:4700:4700::1112', '2606:4700:4700::1002')
  New-Resolver 'Cloudflare Family' 'F' 'GL' @('1.1.1.3', '1.0.0.3') @('2606:4700:4700::1113', '2606:4700:4700::1003')
  New-Resolver 'Google Public DNS' 'U' 'GL' @('8.8.8.8', '8.8.4.4') @('2001:4860:4860::8888', '2001:4860:4860::8844')
  New-Resolver 'Quad9 (Filtered)' 'F' 'GL' @('9.9.9.9', '149.112.112.112') @('2620:fe::fe', '2620:fe::9')
  New-Resolver 'Quad9 (Unfiltered)' 'U' 'GL' @('9.9.9.10', '149.112.112.10') @('2620:fe::10', '2620:fe::fe:10')
  New-Resolver 'Quad9 (ECS)' 'F' 'GL' @('9.9.9.11', '149.112.112.11') @('2620:fe::11', '2620:fe::fe:11')
  New-Resolver 'OpenDNS Home' 'F' 'GL' @('208.67.222.222', '208.67.220.220') @('2620:119:35::35', '2620:119:53::53')
  New-Resolver 'OpenDNS Family' 'F' 'GL' @('208.67.222.123', '208.67.220.123') @('2620:119:35::123', '2620:119:53::123')
  New-Resolver 'AdGuard Default (ads)' 'A' 'GL' @('94.140.14.14', '94.140.15.15') @('2a10:50c0::ad1:ff', '2a10:50c0::ad2:ff')
  New-Resolver 'AdGuard Family' 'F' 'GL' @('94.140.14.15', '94.140.15.16') @('2a10:50c0::bad1:ff', '2a10:50c0::bad2:ff')
  New-Resolver 'AdGuard Unfiltered' 'U' 'GL' @('94.140.14.140', '94.140.14.141') @('2a10:50c0::1:ff', '2a10:50c0::2:ff')
  New-Resolver 'Control D Unfiltered' 'U' 'GL' @('76.76.2.0', '76.76.10.0') @('2606:1a40::', '2606:1a40:1::')
  New-Resolver 'Control D Malware' 'F' 'GL' @('76.76.2.1', '76.76.10.1') @('2606:1a40::1', '2606:1a40:1::1')
  New-Resolver 'Control D Ads' 'A' 'GL' @('76.76.2.2', '76.76.10.2') @('2606:1a40::2', '2606:1a40:1::2')
  New-Resolver 'NextDNS (Anycast)' 'U' 'GL' @('45.90.28.0', '45.90.30.0') @('2a07:a8c0::', '2a07:a8c1::')
  New-Resolver 'Mullvad DNS' 'U' 'EU' @('194.242.2.2') @('2a07:e340::2')
  New-Resolver 'Mullvad Adblock' 'A' 'EU' @('194.242.2.3') @('2a07:e340::3')
  New-Resolver 'CleanBrowsing Security' 'F' 'GL' @('185.228.168.9', '185.228.169.9') @('2a0d:2a00:1::2', '2a0d:2a00:2::2')
  New-Resolver 'CleanBrowsing Family' 'F' 'GL' @('185.228.168.168', '185.228.169.168') @('2a0d:2a00:1::', '2a0d:2a00:2::')
  New-Resolver 'CleanBrowsing Adult Filter' 'F' 'GL' @('185.228.168.10', '185.228.169.11') @('2a0d:2a00:1::1', '2a0d:2a00:2::1')
  New-Resolver 'DNS.SB' 'U' 'GL' @('185.222.222.222', '45.11.45.11') @('2a09::', '2a11::')
  New-Resolver 'Comodo Secure DNS' 'F' 'NA' @('8.26.56.26', '8.20.247.20') @()
  New-Resolver 'Verisign Public DNS' 'U' 'GL' @('64.6.64.6', '64.6.65.6') @('2620:74:1b::1:1', '2620:74:1c::2:2')
  New-Resolver 'Level3 / Lumen' 'U' 'NA' @('4.2.2.1', '4.2.2.2') @()
  New-Resolver 'Neustar UltraDNS' 'U' 'GL' @('156.154.70.1', '156.154.71.1') @('2610:a1:1018::1', '2610:a1:1019::1')
  New-Resolver 'Hurricane Electric' 'U' 'GL' @('74.82.42.42') @('2001:470:20::2')
  New-Resolver 'Alternate DNS (ads)' 'A' 'GL' @('76.76.19.19', '76.223.122.150') @('2602:fcbc::ad', '2602:fcbc:2::ad')
  New-Resolver 'OpenNIC (anycast)' 'U' 'GL' @('185.121.177.177', '169.239.202.202') @()
  New-Resolver 'CIRA Shield Private' 'U' 'NA' @('149.112.121.10', '149.112.122.10') @('2620:10A:80BB::10', '2620:10A:80BC::10')
  New-Resolver 'CIRA Shield Protected' 'F' 'NA' @('149.112.121.20', '149.112.122.20') @('2620:10A:80BB::20', '2620:10A:80BC::20')
  New-Resolver 'DNS4EU (Unfiltered)' 'U' 'EU' @('86.54.11.100', '86.54.11.200') @('2a13:1001::86:54:11:100', '2a13:1001::86:54:11:200')
  New-Resolver 'DNS0.eu' 'F' 'EU' @('193.110.81.0', '185.253.5.0') @('2a0f:fc80::', '2a0f:fc81::')
  New-Resolver 'DNS0.eu Open' 'U' 'EU' @('193.110.81.254', '185.253.5.254') @('2a0f:fc80::254', '2a0f:fc81::254')
  New-Resolver 'DNS.WATCH' 'U' 'EU' @('84.200.69.80', '84.200.70.40') @('2001:1608:10:25::1c04:b12f', '2001:1608:10:25::9249:d69b')
  New-Resolver 'UncensoredDNS' 'U' 'EU' @('91.239.100.100', '89.233.43.71') @('2001:67c:28a4::', '2a01:3a0:53:53::')
  New-Resolver 'Digitale Gesellschaft' 'U' 'EU' @('185.95.218.42', '185.95.218.43') @('2a02:c205:3001:4558::1', '2a02:c205:3001:4558::2')
  New-Resolver 'SafeDNS' 'F' 'EU' @('195.46.39.39', '195.46.39.40') @()
  New-Resolver 'Yandex Basic' 'U' 'EU' @('77.88.8.8', '77.88.8.1') @('2a02:6b8::feed:0ff', '2a02:6b8:0:1::feed:0ff')
  New-Resolver 'Yandex Safe' 'F' 'EU' @('77.88.8.88', '77.88.8.2') @('2a02:6b8::feed:bad', '2a02:6b8:0:1::feed:bad')
  New-Resolver 'Yandex Family' 'F' 'EU' @('77.88.8.7', '77.88.8.3') @('2a02:6b8::feed:a11', '2a02:6b8:0:1::feed:a11')
  New-Resolver 'Quad101 (TWNIC)' 'U' 'AS' @('101.101.101.101', '101.102.103.104') @('2001:de4::101', '2001:de4::102')
  New-Resolver 'AliDNS' 'U' 'AS' @('223.5.5.5', '223.6.6.6') @('2400:3200::1', '2400:3200:baba::1')
  New-Resolver 'DNSPod (Tencent)' 'U' 'AS' @('119.29.29.29', '182.254.116.116') @()
  New-Resolver 'Baidu DNS' 'U' 'AS' @('180.76.76.76') @('2400:da00::6666')
  New-Resolver '114DNS' 'U' 'AS' @('114.114.114.114', '114.114.115.115') @()
  New-Resolver 'CNNIC SDNS' 'U' 'AS' @('1.2.4.8', '210.2.4.8') @()
  New-Resolver 'KT (Korea Telecom)' 'U' 'AS' @('168.126.63.1', '168.126.63.2') @()
  New-Resolver 'LG U+ (Korea)' 'U' 'AS' @('164.124.101.2', '203.248.252.2') @()
  New-Resolver 'SingTel (Singapore)' 'U' 'AS' @('165.21.83.88', '165.21.100.88') @()
  New-Resolver 'dnsforge.de (ads)' 'A' 'EU' @('176.9.93.198') @()
)

# =====================================================================
# low-level probes
# =====================================================================
function Resolve-Timed {
  param(
    [string]$Server,
    [string]$Name,
    [string]$Type = 'A',
    [switch]$NoRetry
  )
  $watch = [System.Diagnostics.Stopwatch]::StartNew()
  $status = 'NOERROR'
  $answers = @()
  try {
    $lookup = @{
      Name = $Name; Type = $Type
      DnsOnly = $true; ErrorAction = 'Stop'
    }
    if ($Server) { $lookup['Server'] = $Server }
    if ($NoRetry) { $lookup['QuickTimeout'] = $true }
    $records = Resolve-DnsName @lookup
    $answers = @($records | Where-Object { $_.IPAddress } | ForEach-Object { $_.IPAddress })
  } catch {
    $message = "$($_.Exception.Message) $($_.FullyQualifiedErrorId)"
    if ($message -match 'does not exist|NXDOMAIN|NAME_ERROR') { $status = 'NXDOMAIN' }
    elseif ($message -match 'server failure|SERVFAIL') { $status = 'SERVFAIL' }
    elseif ($message -match 'refused|REFUSED') { $status = 'REFUSED' }
    elseif ($message -match 'timed out|timeout|no response|unreachable|network is unreachable') { $status = 'TIMEOUT' }
    else { $status = 'ERROR' }
  }
  $watch.Stop()
  [pscustomobject]@{
    Ms = [int]$watch.ElapsedMilliseconds
    Status = $status
    Answers = $answers
  }
}

function Get-DnsStats {
  param([string]$Server, [string]$Mode, [int]$Count, [int]$ResolverIndex = 0)
  if (-not $Server -or $Server -eq 'none') {
    return [pscustomobject]@{ Median = $null; Min = $null; Max = $null; Loss = 0 }
  }
  $times = New-Object System.Collections.Generic.List[int]
  $fails = 0
  $tries = $Count
  if ($Mode -eq 'cached') { $tries = $Count + 1 }
  for ($i = 1; $i -le $tries; $i++) {
    if ($Mode -eq 'cold') {
      $query = New-ColdName -ResolverIndex $ResolverIndex -SampleIndex $i
    } else {
      $query = $Domain
    }
    $result = Resolve-Timed -Server $Server -Name $query -NoRetry
    if ($Mode -eq 'cached' -and $i -eq 1) { continue }
    $ok = if ($Mode -eq 'cold') {
      ($result.Status -eq 'NXDOMAIN' -or $result.Status -eq 'NOERROR')
    } else {
      ($result.Status -eq 'NOERROR' -and $result.Answers.Count -gt 0)
    }
    if ($ok) { $times.Add($result.Ms) } else { $fails++ }
    if ($times.Count -eq 0 -and $fails -ge 3) { break }
  }
  if ($times.Count -eq 0) {
    return [pscustomobject]@{ Median = $null; Min = $null; Max = $null; Loss = 100 }
  }
  $sorted = @($times | Sort-Object)
  $median = $sorted[[int][math]::Floor(($sorted.Count - 1) / 2)]
  [pscustomobject]@{
    Median = $median
    Min = $sorted[0]
    Max = $sorted[$sorted.Count - 1]
    Loss = [int]($fails * 100 / $tries)
  }
}

function Get-PingStats {
  param([string]$Target, [int]$Count = 3)
  if (-not $Target -or $Target -eq 'none') {
    return [pscustomobject]@{ Avg = $null; Loss = 100 }
  }
  $ping = New-Object System.Net.NetworkInformation.Ping
  $times = @()
  $fails = 0
  for ($i = 0; $i -lt $Count; $i++) {
    try {
      $reply = $ping.Send($Target, 2000)
      if ($reply.Status -eq 'Success') { $times += [int]$reply.RoundtripTime } else { $fails++ }
    } catch { $fails++ }
  }
  $ping.Dispose()
  if ($times.Count -eq 0) {
    return [pscustomobject]@{ Avg = $null; Loss = 100 }
  }
  [pscustomobject]@{
    Avg = [math]::Round(($times | Measure-Object -Average).Average, 1)
    Loss = [int]($fails * 100 / $Count)
  }
}

function Get-PingDetail {
  param([string]$Target, [int]$Count = 5)
  if (-not $Target) {
    return [pscustomobject]@{ Avg = $null; Jitter = 0; Loss = 100 }
  }
  $ping = New-Object System.Net.NetworkInformation.Ping
  $times = @()
  $fails = 0
  for ($i = 0; $i -lt $Count; $i++) {
    try {
      $reply = $ping.Send($Target, 1500)
      if ($reply.Status -eq 'Success') { $times += [double]$reply.RoundtripTime } else { $fails++ }
    } catch { $fails++ }
  }
  $ping.Dispose()
  if ($times.Count -eq 0) {
    return [pscustomobject]@{ Avg = $null; Jitter = 0; Loss = 100 }
  }
  $avg = ($times | Measure-Object -Average).Average
  $variance = 0.0
  foreach ($value in $times) { $variance += [math]::Pow($value - $avg, 2) }
  $jitter = [math]::Sqrt($variance / $times.Count)
  [pscustomobject]@{
    Avg = [math]::Round($avg, 1)
    Jitter = [math]::Round($jitter, 1)
    Loss = [int]($fails * 100 / $Count)
  }
}

function Test-TcpPort {
  param([string]$Target, [int]$Port, [int]$TimeoutMs = 3000)
  $client = New-Object System.Net.Sockets.TcpClient
  try {
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $task = $client.ConnectAsync($Target, $Port)
    if (-not $task.Wait($TimeoutMs)) { return $null }
    $watch.Stop()
    if ($client.Connected) { return [int]$watch.ElapsedMilliseconds }
    return $null
  } catch {
    return $null
  } finally {
    $client.Close()
  }
}

function Test-Dnssec {
  param([string]$Server)
  $ok = $false
  $bad = $false
  $r1 = Resolve-Timed -Server $Server -Name 'sigok.verteiltesysteme.net' -NoRetry
  if ($r1.Status -eq 'NOERROR' -and $r1.Answers.Count -gt 0) { $ok = $true }
  $r2 = Resolve-Timed -Server $Server -Name 'sigfail.verteiltesysteme.net' -NoRetry
  if ($r2.Status -eq 'NOERROR' -and $r2.Answers.Count -gt 0) { $bad = $true }
  if ($ok -and -not $bad) { return 'yes' }
  if ($ok -and $bad) { return 'no' }
  return '?'
}

function Test-NxHijack {
  param([string]$Server, [int]$Index = 0)
  $query = New-NxProbeName -ResolverIndex $Index
  $result = Resolve-Timed -Server $Server -Name $query -NoRetry
  if ($result.Status -eq 'NXDOMAIN') { return 'ok' }
  if ($result.Status -eq 'NOERROR' -and $result.Answers.Count -gt 0) { return 'HIJACK' }
  return '?'
}

function Test-AdBlock {
  param([string]$Server)
  $blocked = 0
  $seen = 0
  foreach ($name in @('doubleclick.net', 'googleadservices.com', 'pagead2.googlesyndication.com')) {
    $result = Resolve-Timed -Server $Server -Name $name -NoRetry
    if ($result.Status -eq 'TIMEOUT') { continue }
    $seen++
    if ($result.Status -eq 'NXDOMAIN' -or $result.Status -eq 'REFUSED') { $blocked++; continue }
    if ($result.Status -eq 'NOERROR') {
      if ($result.Answers.Count -eq 0) { $blocked++; continue }
      if ($result.Answers[0] -match '^(0\.0\.0\.0|127\.|146\.112\.61\.)') { $blocked++ }
    }
  }
  if ($seen -eq 0) { return '?' }
  if ($blocked * 2 -gt $seen) { return 'yes' }
  return 'no'
}

function Get-DnsPop {
  param([string]$Server)
  foreach ($query in @('id.server', 'hostname.bind')) {
    try {
      $records = Resolve-DnsName -Name $query -Type TXT -Class CH -Server $Server -DnsOnly -QuickTimeout -ErrorAction Stop
      $text = ($records | Where-Object { $_.Strings } | Select-Object -First 1).Strings
      if ($text) {
        $value = ($text -join ' ')
        if ($value.Length -gt 22) { $value = $value.Substring(0, 22) }
        return $value
      }
    } catch { }
  }
  return '-'
}

function Get-Score($Cached, $Cold, $Loss) {
  if ($null -eq $Cached) { return 99999.0 }
  $c = [double]$Cached
  if ($null -ne $Cold) { $base = ($c + 2.0 * [double]$Cold) / 3.0 } else { $base = $c * 3.0 }
  return [math]::Round($base + [double]$Loss * 3.0, 1)
}

# =====================================================================
# platform: adapters and DNS
# =====================================================================
function Get-ActiveAdapter {
  $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
    Sort-Object { $_.RouteMetric + $_.InterfaceMetric } | Select-Object -First 1
  if (-not $route) { return $null }
  Get-NetAdapter -InterfaceIndex $route.InterfaceIndex -ErrorAction SilentlyContinue
}

function Get-SystemDns {
  $adapter = Get-ActiveAdapter
  if (-not $adapter) { return @() }
  $servers = (Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses
  @($servers | Where-Object { $_ })
}

function Test-IPv6Working {
  $probe = Resolve-Timed -Server '2606:4700:4700::1111' -Name 'cloudflare.com' -NoRetry
  return ($probe.Status -eq 'NOERROR' -and $probe.Answers.Count -gt 0)
}

function Test-Admin {
  if ($script:IsAdmin) { return $true }
  Write-Host '  Changing DNS needs an elevated PowerShell (Run as Administrator).' -ForegroundColor Yellow
  return $false
}

function Save-Backup {
  $file = Join-Path $HOME '.dns-bench-previous.txt'
  $adapter = Get-ActiveAdapter
  $line = '{0} adapter={1} dns={2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $adapter.Name, ((Get-SystemDns) -join ',')
  Add-Content -Path $file -Value $line -ErrorAction SilentlyContinue
}

function Set-DnsServers {
  param([string[]]$Servers)
  $adapter = Get-ActiveAdapter
  if (-not $adapter) { throw 'no active network adapter found' }
  if (-not (Test-Admin)) { return $false }
  Save-Backup
  Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $Servers -ErrorAction Stop
  Clear-DnsClientCache -ErrorAction SilentlyContinue
  return $true
}

function Reset-DnsServers {
  $adapter = Get-ActiveAdapter
  if (-not $adapter) { throw 'no active network adapter found' }
  if (-not (Test-Admin)) { return $false }
  Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ResetServerAddresses -ErrorAction Stop
  Clear-DnsClientCache -ErrorAction SilentlyContinue
  return $true
}

function Get-DnsMode {
  $adapter = Get-ActiveAdapter
  if (-not $adapter) { return 'unknown' }
  $setting = Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ErrorAction SilentlyContinue
  $servers = @($setting | ForEach-Object { $_.ServerAddresses } | Where-Object { $_ } | Select-Object -Unique)
  if ($servers.Count -eq 0) { return 'automatic (DHCP/router)' }
  return 'manual: ' + ($servers -join ', ')
}

function Build-Resolvers {
  $script:Resolvers = @($script:Resolvers)
  $gateway = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
    Sort-Object { $_.RouteMetric + $_.InterfaceMetric } | Select-Object -First 1).NextHop
  if ($gateway) {
    $probe = Resolve-Timed -Server $gateway -Name $Domain -NoRetry
    if ($probe.Status -eq 'NOERROR') {
      $script:Resolvers += New-Resolver 'Router / Gateway' 'C' 'LAN' @($gateway) @()
    }
  }
  $system = Get-SystemDns
  if ($system.Count -gt 0 -and $system[0] -ne $gateway) {
    $script:Resolvers += New-Resolver 'Current system DNS' 'C' 'LAN' @($system[0]) @()
  }
}

# =====================================================================
# benchmark
# =====================================================================
function Invoke-Probe {
  param([int]$Index)
  $resolver = $script:Resolvers[$Index - 1]
  $primary = $resolver.V4[0]
  # PS1 runs every probe in one process, so the RNG state is shared. Reseed
  # from a fresh GUID at the start of each probe (before any random is drawn)
  # so sequential resolvers cannot pick the same sample/name pattern.
  $seed = [guid]::NewGuid().GetHashCode() -band 0x7FFFFFFF
  if ($seed -eq 0) { $seed = 1 }
  Get-Random -SetSeed $seed | Out-Null
  $cached = $null; $cold = $null; $jitter = $null; $loss = 100
  $v4ping = $null; $v6dns = 'N/A'; $v6ping = 'N/A'
  $dnssec = '-'; $nx = '-'; $tcp = '-'; $dot = '-'; $doh = '-'; $ads = '-'; $pop = '-'

  $stats = Get-DnsStats -Server $primary -Mode 'cached' -Count $Samples -ResolverIndex $Index
  if ($null -ne $stats.Median) {
    $cached = $stats.Median
    $jitter = $stats.Max - $stats.Min
    $loss = $stats.Loss
    $coldStats = Get-DnsStats -Server $primary -Mode 'cold' -Count 3 -ResolverIndex $Index
    if ($null -ne $coldStats.Median) { $cold = $coldStats.Median }
    $nx = Test-NxHijack -Server $primary -Index $Index
    if (-not $Quick) {
      $v4ping = (Get-PingStats -Target $primary).Avg
      if ($script:HasV6 -and $resolver.V6.Count -gt 0) {
        $v6Stats = Get-DnsStats -Server $resolver.V6[0] -Mode 'cached' -Count 3
        if ($null -ne $v6Stats.Median) { $v6dns = $v6Stats.Median } else { $v6dns = 'Timeout' }
        $ping6 = Get-PingStats -Target $resolver.V6[0]
        if ($null -ne $ping6.Avg) { $v6ping = $ping6.Avg } else { $v6ping = 'Timeout' }
      }
      $dnssec = Test-Dnssec -Server $primary
      $tcp = if ($null -ne (Test-TcpPort -Target $primary -Port 53)) { 'yes' } else { 'no' }
      $dot = if ($null -ne (Test-TcpPort -Target $primary -Port 853)) { 'yes' } else { 'no' }
      $doh = if ($null -ne (Test-TcpPort -Target $primary -Port 443)) { 'yes' } else { 'no' }
      $pop = Get-DnsPop -Server $primary
    }
    if ((-not $Quick) -or $resolver.Kind -eq 'A') {
      $ads = Test-AdBlock -Server $primary
    }
  }

  $score = Get-Score -Cached $cached -Cold $cold -Loss $loss
  $cachedText = 'Timeout'; if ($null -ne $cached) { $cachedText = $cached }
  $jitterText = '-'; if ($null -ne $jitter) { $jitterText = $jitter }
  $coldText = '-'; if ($null -ne $cold) { $coldText = $cold }
  $scoreText = '-'; if ($score -lt 99999) { $scoreText = $score }
  $v4pingText = '-'; if ($null -ne $v4ping) { $v4pingText = $v4ping }
  [pscustomobject]@{
    SortKey = $score
    Index = $Index
    Name = $resolver.Name
    Kind = $resolver.Kind
    Region = $resolver.Region
    Cached = $cachedText
    Jitter = $jitterText
    Loss = $loss
    Cold = $coldText
    Score = $scoreText
    V4Ping = $v4pingText
    V6Dns = $v6dns
    V6Ping = $v6ping
    Dnssec = $dnssec
    Nx = $nx
    Tcp = $tcp
    Dot = $dot
    Doh = $doh
    Ads = $ads
    Pop = $pop
  }
}

function Invoke-Benchmark {
  param([string]$Kinds = '')
  $targets = @()
  for ($i = 1; $i -le $script:Resolvers.Count; $i++) {
    $resolver = $script:Resolvers[$i - 1]
    if ($Kinds -and (" $Kinds " -notlike "* $($resolver.Kind) *")) { continue }
    $targets += $i
  }
  $results = New-Object System.Collections.Generic.List[object]
  $done = 0
  foreach ($index in $targets) {
    $resolver = $script:Resolvers[$index - 1]
    if (-not $NoProgress) {
      Write-Progress -Id 1 -Activity 'dns-bench: probing resolvers' `
        -Status ("{0} ({1}/{2})" -f $resolver.Name, ($done + 1), $targets.Count) `
        -PercentComplete ([int]($done * 100 / [math]::Max(1, $targets.Count)))
    }
    $results.Add((Invoke-Probe -Index $index))
    $done++
  }
  if (-not $NoProgress) { Write-Progress -Id 1 -Activity 'dns-bench: probing resolvers' -Completed }
  $script:Results = @($results | Sort-Object SortKey)
}

function Show-Table {
  $header = '  {0,4} {1,4} {2,-26} {3,-4} {4,-4} {5,9} {6,8} {7,6} {8,9} {9,7} {10,9} {11,9} {12,9}'
  Write-Host ($header -f 'Rank', '#', 'Provider', 'Rgn', 'Kind', 'Cached', 'Jitter', 'Loss', 'Cold', 'Score', 'v4 ping', 'v6 DNS', 'v6 ping') -ForegroundColor White
  Write-Host ('  ' + ('-' * 118)) -ForegroundColor DarkGray
  $rank = 1
  foreach ($row in $script:Results) {
    $color = if ($rank -eq 1) { 'White' } else { 'Gray' }
    $cachedText = if ($row.Cached -is [ValueType]) { "$($row.Cached) ms" } else { $row.Cached }
    $coldText = if ($row.Cold -is [ValueType]) { "$($row.Cold) ms" } else { $row.Cold }
    $jitterText = if ($row.Jitter -is [ValueType]) { "$($row.Jitter) ms" } else { $row.Jitter }
    $v4Text = if ($row.V4Ping -is [ValueType]) { "$($row.V4Ping) ms" } else { $row.V4Ping }
    $v6Text = if ($row.V6Dns -is [ValueType]) { "$($row.V6Dns) ms" } else { $row.V6Dns }
    $v6pText = if ($row.V6Ping -is [ValueType]) { "$($row.V6Ping) ms" } else { $row.V6Ping }
    Write-Host ($header -f $rank, $row.Index, $row.Name, $row.Region, $row.Kind,
      $cachedText, $jitterText, "$($row.Loss)%", $coldText, $row.Score,
      $v4Text, $v6Text, $v6pText) -ForegroundColor $color
    $rank++
  }
  Write-Host '  Kind: U unfiltered | F filters content | A blocks ads | C your current/local resolver (baseline)' -ForegroundColor DarkGray

  if ($Quick) { return }
  Write-Host ''
  $features = '  {0,4} {1,-4} {2,-26} {3,-4} {4,7} {5,6} {6,7} {7,6} {8,6} {9,6} {10,-22}'
  Write-Host ($features -f '#', 'Rgn', 'Provider', 'Kind', 'DNSSEC', 'NX', 'TCP/53', 'DoT', '443', 'Ads', 'PoP') -ForegroundColor White
  Write-Host ('  ' + ('-' * 104)) -ForegroundColor DarkGray
  foreach ($row in $script:Results) {
    Write-Host ($features -f $row.Index, $row.Region, $row.Name, $row.Kind, $row.Dnssec, $row.Nx,
      $row.Tcp, $row.Dot, $row.Doh, $row.Ads, $row.Pop)
  }
  Write-Host '  DNSSEC yes = validates signatures | NX ok = no NXDOMAIN hijacking | DoT/443 = port reachable' -ForegroundColor DarkGray
}

function Get-BestResolver {
  param([string]$Kind = 'U', [switch]$NeedAds)
  foreach ($row in $script:Results) {
    if ($row.Kind -ne $Kind) { continue }
    if ($row.Cached -eq 'Timeout') { continue }
    if ($row.Loss -gt 20) { continue }
    if ($row.Nx -eq 'HIJACK') { continue }
    if ($NeedAds -and $row.Ads -ne 'yes') { continue }
    return $row
  }
  return $null
}

function Show-GeoTest {
  $regions = @(
    @('North America', 'N. Virginia', 'us-east-1'), @('North America', 'Oregon', 'us-west-2'),
    @('North America', 'Montreal', 'ca-central-1'), @('South America', 'Sao Paulo', 'sa-east-1'),
    @('Europe', 'Ireland', 'eu-west-1'), @('Europe', 'Frankfurt', 'eu-central-1'),
    @('Europe', 'Stockholm', 'eu-north-1'), @('Middle East', 'Bahrain', 'me-south-1'),
    @('Middle East', 'UAE', 'me-central-1'), @('Africa', 'Cape Town', 'af-south-1'),
    @('Asia', 'Mumbai', 'ap-south-1'), @('Asia', 'Hyderabad', 'ap-south-2'),
    @('Asia', 'Singapore', 'ap-southeast-1'), @('Asia', 'Hong Kong', 'ap-east-1'),
    @('Asia', 'Tokyo', 'ap-northeast-1'), @('Oceania', 'Sydney', 'ap-southeast-2')
  )
  Write-Section 'Latency to each continent (TCP connect, median of 3)'
  $best = $null
  $bestMs = 99999
  $i = 0
  foreach ($region in $regions) {
    $i++
    if (-not $NoProgress) {
      Write-Progress -Id 2 -Activity 'dns-bench: continents' -Status $region[1] -PercentComplete ([int]($i * 100 / $regions.Count))
    }
    $times = @()
    for ($k = 0; $k -lt 3; $k++) {
      $ms = Test-TcpPort -Target ("ec2.{0}.amazonaws.com" -f $region[2]) -Port 443 -TimeoutMs 3000
      if ($null -ne $ms) { $times += $ms }
    }
    if ($times.Count -eq 0) {
      $median = 'Timeout'
    } else {
      $sorted = @($times | Sort-Object)
      $median = $sorted[[int][math]::Floor(($sorted.Count - 1) / 2)]
    }
    $bar = ''
    if ($median -ne 'Timeout') {
      $blocks = [int]([math]::Min(30, $median / 12))
      $bar = ' ' + ('#' * $blocks)
      if ($median -lt $bestMs) { $bestMs = $median; $best = "$($region[1]) ($($region[0]))" }
    }
    Write-Host ('  {0,-16} {1,-14} {2,-16} {3,8}{4}' -f $region[0], $region[1], $region[2], "$median ms", $bar)
  }
  if (-not $NoProgress) { Write-Progress -Id 2 -Activity 'dns-bench: continents' -Completed }
  if ($best) { Write-Note "Closest cloud region: $best at $bestMs ms. Region latency is physical distance, it does not depend on your DNS choice." }
}

function Show-ServiceTest {
  param([object[]]$Resolvers)
  $services = @(
    @('Google', 'www.google.com'), @('YouTube', 'www.youtube.com'), @('Google Meet', 'meet.google.com'),
    @('Facebook', 'www.facebook.com'), @('Instagram', 'www.instagram.com'), @('WhatsApp Web', 'web.whatsapp.com'),
    @('X / Twitter', 'x.com'), @('LinkedIn', 'www.linkedin.com'), @('Reddit', 'www.reddit.com'),
    @('Netflix', 'www.netflix.com'), @('Prime Video', 'www.primevideo.com'), @('Spotify', 'open.spotify.com'),
    @('Hotstar', 'www.hotstar.com'), @('Apple', 'www.apple.com'), @('Microsoft', 'www.microsoft.com'),
    @('Teams', 'teams.microsoft.com'), @('Zoom', 'zoom.us'), @('Amazon', 'www.amazon.com'),
    @('Flipkart', 'www.flipkart.com'), @('GitHub', 'github.com'), @('npm registry', 'registry.npmjs.org'),
    @('PyPI', 'pypi.org'), @('Docker Hub', 'registry-1.docker.io'), @('OpenAI API', 'api.openai.com'),
    @('Anthropic API', 'api.anthropic.com'), @('cdnjs', 'cdnjs.cloudflare.com'), @('jsDelivr', 'cdn.jsdelivr.net'),
    @('AWS S3', 's3.amazonaws.com'), @('Steam', 'store.steampowered.com'), @('Wikipedia', 'www.wikipedia.org')
  )
  if ($ExtraServices) {
    foreach ($host_ in ($ExtraServices -split ',')) {
      $clean = $host_.Trim()
      if ($clean -match '^[A-Za-z0-9.-]+$') { $services += , @($clean, $clean) }
    }
  }

  Write-Section ("Popular services: edge RTT returned by each resolver ({0} services x {1} resolvers)" -f $services.Count, $Resolvers.Count)
  Write-Note 'Each value = TCP connect time to the IP that resolver handed back. Lower = closer CDN edge.'

  $stats = @{}
  foreach ($resolver in $Resolvers) {
    $stats[$resolver.Index] = [pscustomobject]@{
      Resolver = $resolver.Name; Index = $resolver.Index
      SumRtt = 0; CountRtt = 0; SumLookup = 0; CountLookup = 0; Wins = 0; Failed = 0
    }
  }
  $bestRow = $null
  $bestAvg = 99999
  $i = 0
  foreach ($service in $services) {
    $i++
    if (-not $NoProgress) {
      Write-Progress -Id 3 -Activity 'dns-bench: popular services' -Status $service[0] -PercentComplete ([int]($i * 100 / $services.Count))
    }
    $row = @{}
    $rowMin = 99999
    foreach ($resolver in $Resolvers) {
      $full = $script:Resolvers[$resolver.Index - 1]
      $lookup = Resolve-Timed -Server $full.V4[0] -Name $service[1] -NoRetry
      $ip = if ($lookup.Answers.Count -gt 0) { $lookup.Answers[0] } else { $null }
      if ($null -eq $ip) {
        $rtt = 'NoAnswer'
      } elseif ($ip -match '^(0\.0\.0\.0|127\.|146\.112\.61\.)') {
        $rtt = 'Blocked'
      } else {
        $ms = Test-TcpPort -Target $ip -Port 443 -TimeoutMs 3000
        $rtt = if ($null -ne $ms) { $ms } else { 'Timeout' }
      }
      $row[$resolver.Index] = $rtt
      $entry = $stats[$resolver.Index]
      if ($lookup.Status -eq 'NOERROR') {
        $entry.SumLookup += $lookup.Ms; $entry.CountLookup++
      }
      if ($rtt -is [int]) {
        $entry.SumRtt += $rtt; $entry.CountRtt++
        if ($rtt -lt $rowMin) { $rowMin = $rtt }
      } else {
        $entry.Failed++
      }
    }
    $line = '  {0,-20}' -f $service[0]
    foreach ($resolver in $Resolvers) {
      $value = $row[$resolver.Index]
      $cell = if ($value -is [int]) { '{0,9}' -f "$value ms" } else { '{0,9}' -f $value }
      $line += $cell
    }
    Write-Host $line
    foreach ($resolver in $Resolvers) {
      $value = $row[$resolver.Index]
      if ($value -is [int] -and $value -le $rowMin + 3) { $stats[$resolver.Index].Wins++ }
    }
  }
  if (-not $NoProgress) { Write-Progress -Id 3 -Activity 'dns-bench: popular services' -Completed }

  Write-Host ''
  Write-Host ('  {0,-26} {1,14} {2,12} {3,13} {4,8}' -f 'Resolver summary', 'Avg edge RTT', 'Avg lookup', 'Best-in-row', 'Failed') -ForegroundColor White
  foreach ($resolver in $Resolvers) {
    $entry = $stats[$resolver.Index]
    $avg = if ($entry.CountRtt -gt 0) { [int]($entry.SumRtt / $entry.CountRtt) } else { 'n/a' }
    $avgLookup = if ($entry.CountLookup -gt 0) { [int]($entry.SumLookup / $entry.CountLookup) } else { 'n/a' }
    Write-Host ('  {0,-26} {1,14} {2,12} {3,13} {4,8}' -f $entry.Resolver, "$avg ms", "$avgLookup ms",
      "$($entry.Wins)/$($services.Count)", $entry.Failed)
    if ($resolver.Kind -eq 'U' -and $avg -ne 'n/a' -and $avg -lt $bestAvg -and
        ($entry.Failed * 100 / $services.Count) -le 20) {
      $bestAvg = $avg
      $bestRow = [pscustomobject]@{ Name = $resolver.Name; Index = $resolver.Index; Avg = $avg }
    }
  }
  return $bestRow
}

function Export-ResultsCsv([string]$Path) {
  if (-not $Path) {
    if ($NoCsv) { return }
    $dir = if ($env:DNSBENCH_CSV_DIR) { $env:DNSBENCH_CSV_DIR } else { $script:SelfDir }
    if (-not (Test-Path $dir)) { $dir = $HOME }
    if (-not (Test-Path $dir)) { $dir = (Get-Location).Path }
    $Path = Join-Path $dir ('dns-bench-{0}-{1}.csv' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd-HHmmss'))
  }
  $rows = foreach ($row in $script:Results) {
    [pscustomobject][ordered]@{
      sortkey = ('{0:0000000.0}' -f $row.SortKey)
      idx = $row.Index
      name = $row.Name
      kind = $row.Kind
      region = $row.Region
      cached_ms = $row.Cached
      jitter_ms = $row.Jitter
      loss_pct = $row.Loss
      cold_ms = $row.Cold
      score = $row.Score
      v4_ping = $row.V4Ping
      v6_dns = $row.V6Dns
      v6_ping = $row.V6Ping
      dnssec = $row.Dnssec
      nxdomain = $row.Nx
      tcp53 = $row.Tcp
      dot853 = $row.Dot
      port443 = $row.Doh
      blocks_ads = $row.Ads
      pop = $row.Pop
    }
  }
  try {
    $csvParams = @{ Path = $Path; Encoding = 'UTF8' }
    if ($PSVersionTable.PSVersion.Major -lt 6) { $csvParams['NoTypeInformation'] = $true }
    $rows | Export-Csv @csvParams
    Write-Host "  Results saved to $Path" -ForegroundColor Cyan
  } catch {
    Write-Warn2 "could not write CSV to $Path"
  }
}

# =====================================================================
# network info
# =====================================================================
function Show-NetworkInfo {
  $adapter = Get-ActiveAdapter
  $systemDns = Get-SystemDns
  Write-Section 'Network'
  Write-Kv 'Host' ("{0} | {1} | {2}" -f $env:COMPUTERNAME, [Environment]::OSVersion.VersionString, $env:PROCESSOR_ARCHITECTURE)
  if (-not $adapter) {
    Write-Bad '  no default route: you appear to be offline'
    return
  }
  Write-Kv 'Active adapter' ("{0} ({1})" -f $adapter.Name, $adapter.InterfaceDescription)
  Write-Kv 'Link speed' ("{0} Mbps" -f [int]($adapter.LinkSpeed / 1000000))
  Write-Kv 'MAC / MTU' ("{0} / {1}" -f $adapter.MacAddress, $adapter.MtuSize)
  $ips = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -ErrorAction SilentlyContinue
  $v4 = @($ips | Where-Object { $_.AddressFamily -eq 'IPv4' -and $_.IPAddress -notmatch '^169\.254\.' } | ForEach-Object { $_.IPAddress })
  $v6 = @($ips | Where-Object { $_.AddressFamily -eq 'IPv6' -and $_.IPAddress -notmatch '^fe80' } | ForEach-Object { $_.IPAddress })
  Write-Kv 'Local IPv4' (($v4 -join ', '))
  Write-Kv 'Local IPv6' (($v6 -join ', '))
  $gateway = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
    Sort-Object { $_.RouteMetric + $_.InterfaceMetric } | Select-Object -First 1).NextHop
  Write-Kv 'Gateway' $gateway
  if ($gateway) {
    $ping = Get-PingStats -Target $gateway -Count 3
    Write-Kv 'Gateway latency' ("{0} ms, loss {1}%" -f $ping.Avg, $ping.Loss)
  }
  $proxy = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
  $proxyText = if ($proxy -and $proxy.ProxyEnable -eq 1) { $proxy.ProxyServer } else { 'none' }
  Write-Kv 'System proxy' $proxyText
  $vpn = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -match 'VPN|WireGuard|OpenVPN|Tailscale|TAP-Windows|Wintun' })
  $vpnText = 'no'
  if ($vpn.Count -gt 0) { $vpnText = "yes ($($vpn.Count))" }
  Write-Kv 'VPN connected' $vpnText
  Write-Kv 'System DNS (in use)' (($systemDns -join ', '))
  Write-Kv 'DNS source' (Get-DnsMode)
  $ssid = (netsh wlan show interfaces 2>$null | Select-String '^\s*SSID\s*:' | Select-Object -First 1)
  if ($ssid) { Write-Kv 'Wi-Fi network' (($ssid.Line -split ':', 2)[1].Trim()) }

  if ($Privacy) {
    Write-Note 'Privacy mode: skipping external IP/geo lookups.'
    return
  }
  try {
    $trace = (Invoke-WebRequest -Uri 'https://1.1.1.1/cdn-cgi/trace' -UseBasicParsing -TimeoutSec 5).Content
    $map = @{}
    foreach ($line in ($trace -split "`n")) {
      $kvp = $line -split '=', 2
      if ($kvp.Count -eq 2) { $map[$kvp[0]] = $kvp[1] }
    }
    $publicText = 'unknown'
    if ($map['ip']) {
      if ($map['ip'] -match ':') { $publicText = 'none (IPv4-only connection)' } else { $publicText = $map['ip'] }
    }
    Write-Kv 'Public IPv4' $publicText
    if ($map['colo']) { Write-Kv 'Nearest Cloudflare PoP' ("{0} (WARP: {1})" -f $map['colo'], $map['warp']) }
  } catch {
    Write-Note 'External IP lookup unavailable.'
  }
  try {
    $geo = Invoke-RestMethod -Uri 'https://ipwho.is/' -TimeoutSec 6
    if ($geo.city) {
      Write-Kv 'Location' ("{0}, {1}, {2} [{3}]" -f $geo.city, $geo.region, $geo.country, $geo.continent)
      Write-Kv 'ISP / ASN' ("{0} (AS{1})" -f $geo.connection.isp, $geo.connection.asn)
      Write-Kv 'Time zone' $geo.timezone.id
    }
  } catch {
    Write-Note 'Geo lookup unavailable (ipwho.is unreachable).'
  }
  try {
    $captive = (Invoke-WebRequest -Uri 'http://www.msftconnecttest.com/connecttest.txt' -UseBasicParsing -TimeoutSec 4).Content
    if ($captive -match 'Microsoft Connect Test') { Write-Kv 'Captive portal' 'no' } else { Write-Kv 'Captive portal' 'possible' }
  } catch {
    Write-Kv 'Captive portal' 'possible / no internet over HTTP'
  }
}

# =====================================================================
# commands
# =====================================================================
function Invoke-Run {
  Build-Resolvers
  $script:HasV6 = Test-IPv6Working
  $script:Resolvers = @($script:Resolvers)
  Write-Host ("dns-bench {0}  {1}  |  target: {2}  |  samples: {3}" -f $script:Version,
    (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Domain, $Samples) -ForegroundColor White
  Show-NetworkInfo
  Write-Section ("DNS benchmark: {0} resolvers" -f $script:Resolvers.Count)
  Write-Note ("Cached = median of {0} queries for {1} | Cold = median of 3 random uncached names | Score = (cached + 2*cold)/3 + 3*loss%%" -f $Samples, $Domain)
  Invoke-Benchmark
  Show-Table

  $best = Get-BestResolver -Kind 'U'
  if (-not $best) {
    Write-Bad 'No unfiltered resolver responded. Check your internet connection.'
    return
  }
  $serviceBest = $null
  if (-not $SkipGeo) { Show-GeoTest }
  if (-not $SkipServices) {
    $top = @($script:Results | Where-Object { $_.Kind -eq 'U' -and $_.Cached -ne 'Timeout' -and $_.Nx -ne 'HIJACK' } | Select-Object -First $TopK)
    $current = $script:Results | Where-Object { $_.Name -eq 'Current system DNS' } | Select-Object -First 1
    if ($current) { $top += $current }
    if ($top.Count -gt 0) { $serviceBest = Show-ServiceTest -Resolvers $top }
  }

  Write-Section 'Summary'
  Write-Kv 'Fastest DNS (unfiltered)' ("#{0} {1}: cached {2} ms, score {3}" -f $best.Index, $best.Name, $best.Cached, $best.Score)
  if ($serviceBest) { Write-Kv 'Best for popular services' ("#{0} {1} (avg edge RTT {2} ms)" -f $serviceBest.Index, $serviceBest.Name, $serviceBest.Avg) }
  $current = $script:Results | Where-Object { $_.Name -eq 'Current system DNS' } | Select-Object -First 1
  if ($current) {
    Write-Kv 'Your current DNS' ("{0}: cached {1} ms, cold {2} ms, score {3}" -f $current.Name, $current.Cached, $current.Cold, $current.Score)
    if ($current.Score -ne '-' -and $best.Score -ne '-') {
      $diff = [math]::Round($best.Score - $current.Score)
      if ($diff -gt 5) { Write-Kv '' "the fastest resolver scores $diff points better" }
      else { Write-Kv '' 'already near the top' }
    }
  }
  Export-ResultsCsv -Path $Csv

  if ($ReportOnly) { Write-Host "`nReport only. No changes made."; return }
  if (-not (Get-ActiveAdapter)) { Write-Host "`nNo active adapter, so DNS will not be changed."; return }

  $choice = 'best'
  if (-not $Yes) {
    Write-Host ''
    Write-Host '  [Enter]/best -> apply fastest unfiltered resolver' -ForegroundColor Cyan
    if ($serviceBest) { Write-Host ('  svc          -> apply best for popular services ({0})' -f $serviceBest.Name) }
    Write-Host ("  [1-{0}]       -> apply a specific resolver by its # in the tables" -f $script:Resolvers.Count)
    Write-Host '  reset        -> revert to automatic DNS (DHCP / router)'
    Write-Host '  q            -> quit without changes'
    $choice = Read-Host "`nYour choice"
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = 'best' }
  }
  $choice = $choice.Trim()
  $target = $null
  switch -Regex ($choice) {
    '^(q|Q)$' { Write-Host 'No changes made.'; return }
    '^reset$' {
      if (Reset-DnsServers) { Write-Host 'Done. DNS is back to the DHCP/router default and the cache is flushed.' }
      return
    }
    '^best$' { $target = $best }
    '^svc$' {
      if (-not $serviceBest) { Write-Host 'No service test was run.'; return }
      $target = $script:Results | Where-Object { $_.Index -eq $serviceBest.Index } | Select-Object -First 1
    }
    '^\d+$' {
      $target = $script:Results | Where-Object { $_.Index -eq [int]$choice } | Select-Object -First 1
      if (-not $target) { Write-Host 'Invalid selection. No changes made.'; return }
    }
    default { Write-Host 'Invalid selection. No changes made.'; return }
  }
  if (-not $target) { Write-Host 'Invalid selection. No changes made.'; return }
  if ($target.Kind -eq 'C') { Write-Host "That's your local/current DNS; nothing to apply."; return }
  if ($target.Kind -eq 'F') { Write-Host "Note: $($target.Name) filters/blocks some domains." -ForegroundColor Yellow }
  if ($target.Kind -eq 'A') { Write-Host "Note: $($target.Name) blocks ads/trackers at the DNS level." -ForegroundColor Yellow }
  if ($target.Nx -eq 'HIJACK') { Write-Bad "Warning: $($target.Name) rewrites non-existent domains (NXDOMAIN hijacking)." }

  $resolver = $script:Resolvers[$target.Index - 1]
  $servers = @($resolver.V4)
  if ($script:HasV6 -and $resolver.V6.Count -gt 0) { $servers += $resolver.V6 }
  Write-Host ("`nApplying {0} to '{1}'..." -f $resolver.Name, (Get-ActiveAdapter).Name)
  try {
    if (Set-DnsServers -Servers $servers) {
      Write-Good ('Success. Servers now in use: {0}' -f ((Get-SystemDns) -join ', '))
      Write-Note 'Previous setting logged to ~\.dns-bench-previous.txt. Run "dns-bench.ps1 reset" to go back.'
    }
  } catch {
    Write-Bad "Failed to apply DNS: $($_.Exception.Message)"
  }
}

function Invoke-Best {
  $script:QuickBest = $true
  $SkipServices = $true
  $SkipGeo = $true
  $Quick = $true
  $Samples = 3
  Build-Resolvers
  $script:HasV6 = Test-IPv6Working
  Invoke-Benchmark
  $best = Get-BestResolver -Kind 'U'
  if (-not $best) { Write-Bad 'No unfiltered resolver responded.'; return }
  Write-Host ("`nFastest: #{0} {1} (cached {2} ms, score {3})" -f $best.Index, $best.Name, $best.Cached, $best.Score)
  Export-ResultsCsv -Path $Csv
  if ($ReportOnly) { Write-Host 'Report only. No changes made.'; return }
  if (-not $Yes) {
    $answer = Read-Host 'Apply it? [Y/n]'
    if ($answer -match '^[nN]') { Write-Host 'No changes made.'; return }
  }
  $resolver = $script:Resolvers[$best.Index - 1]
  $servers = @($resolver.V4)
  if ($script:HasV6 -and $resolver.V6.Count -gt 0) { $servers += $resolver.V6 }
  try {
    if (Set-DnsServers -Servers $servers) { Write-Good ("DNS now: {0}" -f ((Get-SystemDns) -join ', ')) }
  } catch { Write-Bad "Failed to apply DNS: $($_.Exception.Message)" }
}

function Invoke-Adblock {
  if ($Argument -eq 'off') {
    Write-Host 'Turning ad-blocking DNS off (back to automatic DNS)...'
    if (Reset-DnsServers) { Write-Host 'Done.' }
    return
  }
  Build-Resolvers
  $script:HasV6 = Test-IPv6Working
  $Quick = $true
  Invoke-Benchmark -Kinds 'A'
  Write-Host ''
  Write-Host ('  {0,-28} {1,10} {2,10} {3,12}' -f 'Resolver', 'Cached', 'Cold', 'Blocks ads') -ForegroundColor White
  foreach ($row in $script:Results) {
    $cachedText = if ($row.Cached -is [ValueType]) { "$($row.Cached) ms" } else { $row.Cached }
    $coldText = if ($row.Cold -is [ValueType]) { "$($row.Cold) ms" } else { $row.Cold }
    Write-Host ('  {0,-28} {1,10} {2,10} {3,12}' -f $row.Name, $cachedText, $coldText, $row.Ads)
  }
  $best = Get-BestResolver -Kind 'A' -NeedAds
  if (-not $best) { Write-Bad 'No ad-blocking resolver answered and verified.'; return }
  Write-Host ("`n  Fastest that blocks: {0} (cached {1} ms)" -f $best.Name, $best.Cached) -ForegroundColor White
  Export-ResultsCsv -Path $Csv
  if ($ReportOnly) { Write-Host '  Report only.'; return }
  if (-not $Yes) {
    $answer = Read-Host '  Apply it? [Y/n]'
    if ($answer -match '^[nN]') { Write-Host 'No changes made.'; return }
  }
  $resolver = $script:Resolvers[$best.Index - 1]
  $servers = @($resolver.V4)
  if ($script:HasV6 -and $resolver.V6.Count -gt 0) { $servers += $resolver.V6 }
  try {
    if (Set-DnsServers -Servers $servers) {
      Write-Good ("  Ad-blocking DNS active: {0}" -f ((Get-SystemDns) -join ', '))
      Write-Note "DNS blocking covers third-party ad/tracker domains. Undo with: .\dns-bench.ps1 adblock off"
    }
  } catch { Write-Bad "failed to apply DNS: $($_.Exception.Message)" }
}

function Invoke-Set {
  if (-not $Argument) { Write-Bad 'usage: .\dns-bench.ps1 set NAME|#'; return }
  Build-Resolvers
  $match = $null
  if ($Argument -match '^\d+$') {
    $wanted = [int]$Argument
    if ($wanted -ge 1 -and $wanted -le $script:Resolvers.Count) { $match = $script:Resolvers[$wanted - 1] }
  } else {
    $match = $script:Resolvers | Where-Object { $_.Name -like "*$Argument*" } | Select-Object -First 1
  }
  if (-not $match) { Write-Bad "no resolver matches '$Argument' (see: list)"; return }
  $script:HasV6 = Test-IPv6Working
  $servers = @($match.V4)
  if ($script:HasV6 -and $match.V6.Count -gt 0) { $servers += $match.V6 }
  Write-Host ("Applying {0} to '{1}'..." -f $match.Name, (Get-ActiveAdapter).Name)
  try {
    if (Set-DnsServers -Servers $servers) { Write-Host ("Done. Servers now in use: {0}" -f ((Get-SystemDns) -join ', ')) }
  } catch { Write-Bad "failed to apply DNS: $($_.Exception.Message)" }
}

function Invoke-Reset {
  Write-Host ("Resetting DNS for '{0}' to automatic..." -f (Get-ActiveAdapter).Name)
  if (Reset-DnsServers) { Write-Host 'Done. DNS is back to the DHCP/router default and the cache is flushed.' }
}

function Invoke-List {
  Write-Host ('{0,-4} {1,-28} {2,-4} {3,-4} {4,-18} {5}' -f '#', 'Name', 'Kind', 'Rgn', 'IPv4', 'IPv6') -ForegroundColor White
  for ($i = 1; $i -le $script:Resolvers.Count; $i++) {
    $resolver = $script:Resolvers[$i - 1]
    Write-Host ('{0,-4} {1,-28} {2,-4} {3,-4} {4,-18} {5}' -f $i, $resolver.Name, $resolver.Kind, $resolver.Region,
      ($resolver.V4 -join ','), ($resolver.V6 -join ','))
  }
}

function Get-CurlExe {
  foreach ($name in @('curl.exe', 'curl')) {
    $command = Get-Command $name -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
  }
  return $null
}

function Quote-Arg([string]$Value) {
  if ($Value -match '\s') { return '"' + $Value + '"' }
  return $Value
}

function Get-HttpNote {
  param([string[]]$Codes)
  if ($Codes -contains '429') { return 'rate-limited (HTTP 429)' }
  if ($Codes -contains '403') { return 'refused the request (HTTP 403)' }
  $real = @($Codes | Where-Object { $_ -and $_ -ne '0' -and $_ -ne '000' })
  if ($real.Count) { return "HTTP $($real -join ', ')" }
  return $null
}

function Measure-SpeedTransfer {
  param(
    [string]$Curl,
    [ValidateSet('download', 'upload')][string]$Mode,
    [int]$Seconds,
    [int]$Streams = 4
  )
  $nullDevice = if ($script:OnWindows) { 'NUL' } else { '/dev/null' }
  $payload = $null
  if ($Mode -eq 'upload') {
    $payload = Join-Path $script:TmpDir 'speed-up.bin'
    if (-not (Test-Path $payload) -or (Get-Item $payload).Length -lt (8 * 1048576)) {
      $buffer = New-Object byte[] (8 * 1048576)
      [IO.File]::WriteAllBytes($payload, $buffer)
    }
  }

  $mirrors = if ($Mode -eq 'download') {
    @(
      [pscustomobject]@{ Name = 'cloudflare'; Url = 'https://speed.cloudflare.com/__down?bytes=50000000&r=' },
      [pscustomobject]@{ Name = 'ovh'; Url = 'https://proof.ovh.net/files/100Mb.dat?r=' }
    )
  } else {
    @([pscustomobject]@{ Name = 'cloudflare'; Url = 'https://speed.cloudflare.com/__up' })
  }

  $failureNote = $null
  foreach ($mirror in $mirrors) {
    $best = $null
    for ($round = 1; $round -le 2; $round++) {
      $procs = @()
      $outFiles = @()
      $bodyFiles = @()
      for ($i = 1; $i -le $Streams; $i++) {
        $out = Join-Path $script:TmpDir "speed-$Mode-$i.txt"
        $body = Join-Path $script:TmpDir "speed-$Mode-$i.bin"
        $outFiles += $out
        $bodyFiles += $body
        $url = $mirror.Url
        if ($Mode -eq 'download') { $url += [guid]::NewGuid().ToString('N') }
        if ($Mode -eq 'download') {
          $args = @('-4', '-sL', '--max-time', "$Seconds", '-o', (Quote-Arg $body), '-w', '%{http_code}', $url)
        } else {
          $args = @('-4', '-s', '--max-time', "$Seconds", '-X', 'POST', '--data-binary', (Quote-Arg "@$payload"),
            '-H', '"Content-Type: application/octet-stream"', '-o', $nullDevice, '-w', '%{http_code}', $url)
        }
        $procs += Start-Process -FilePath $Curl -ArgumentList $args -RedirectStandardOutput $out -NoNewWindow -PassThru
      }

      $watch = [System.Diagnostics.Stopwatch]::StartNew()
      while ($true) {
        $alive = $false
        foreach ($process in $procs) { if (-not $process.HasExited) { $alive = $true } }
        if (-not $alive) { break }
        if (-not $NoProgress) {
          $bytes = 0
          if ($Mode -eq 'download') {
            foreach ($body in $bodyFiles) {
              if (Test-Path $body) { $bytes += (Get-Item $body).Length }
            }
          }
          $pct = [int]([math]::Min(100, ($watch.Elapsed.TotalSeconds / [math]::Max(1, $Seconds)) * 100))
          $status = if ($Mode -eq 'download') {
            '{0:N0} MB, {1:N1}s' -f ($bytes / 1MB), $watch.Elapsed.TotalSeconds
          } else {
            '{0:N1}s' -f $watch.Elapsed.TotalSeconds
          }
          Write-Progress -Id 9 -Activity 'dns-bench: speed test' -Status ("{0}: {1}" -f $Mode, $status) -PercentComplete $pct
        }
        Start-Sleep -Milliseconds 250
      }
      $watch.Stop()
      if (-not $NoProgress) { Write-Progress -Id 9 -Activity 'dns-bench: speed test' -Completed }

      $codes = @()
      foreach ($out in $outFiles) {
        if (Test-Path $out) {
          $raw = (Get-Content -Path $out -Raw -ErrorAction SilentlyContinue)
          if ($raw -match '([0-9]{3})') { $codes += $matches[1] } else { $codes += '000' }
        }
      }
      if ($env:DNSBENCH_DEBUG) {
        Write-Host ('[speed] {0} round {1}: codes={2} elapsed={3:N2}s' -f $mirror.Name, $round, (($codes | Where-Object { $_ }) -join ','), $watch.Elapsed.TotalSeconds)
      }
      if ($codes -notcontains '200') {
        $failureNote = Get-HttpNote -Codes $codes
        if ($round -eq 1) { Start-Sleep -Seconds 1; continue }
        break
      }

      $bytes = 0
      if ($Mode -eq 'download') {
        foreach ($body in $bodyFiles) {
          if (Test-Path $body) { $bytes += (Get-Item $body).Length }
        }
      } else {
        $perStream = (Get-Item $payload).Length
        $bytes = $perStream * @($codes | Where-Object { $_ -eq '200' }).Count
      }

      $elapsed = $watch.Elapsed.TotalSeconds
      if ($elapsed -gt 0.05 -and $bytes -gt 1048576) {
        $mbps = [math]::Round(($bytes * 8) / $elapsed / 1000000, 1)
        $result = [pscustomobject]@{
          Ok = $true; Mbps = $mbps; MB = [math]::Round($bytes / 1MB); Seconds = [math]::Round($elapsed, 1)
          Mirror = $mirror.Name; Note = $null
        }
        if (-not $best -or $result.Mbps -gt $best.Mbps) { $best = $result }
        if ($elapsed -ge ($Seconds * 0.7)) { break }
      } else {
        break
      }
    }

    foreach ($file in $outFiles + $bodyFiles) {
      Remove-Item -Path $file -Force -ErrorAction SilentlyContinue
    }
    if ($best) {
      if ($mirror.Name -ne 'cloudflare') { $best.Note = $failureNote }
      return $best
    }
  }

  $failed = [pscustomobject]@{ Ok = $false; Mbps = 0; MB = 0; Seconds = 0; Mirror = $null; Note = $failureNote }
  return $failed
}

function Invoke-Speed {
  Write-Section 'Speed test'
  Write-Note "Cloudflare edge (OVH fallback), 4 parallel streams, IPv4. Measures the link itself, not your DNS choice."

  $target = '1.1.1.1'
  $latency = Get-PingDetail -Target $target -Count 5
  if ($null -eq $latency.Avg) {
    $target = '8.8.8.8'
    $latency = Get-PingDetail -Target $target -Count 5
  }
  if ($null -ne $latency.Avg) {
    Write-Host ('  {0,-24} {1} ms   (jitter {2} ms, {3}% loss)' -f "Latency to $target", $latency.Avg, $latency.Jitter, $latency.Loss)
  } else {
    Write-Warn2 'latency probe failed (ICMP blocked or offline)'
  }

  $curl = Get-CurlExe
  if (-not $curl) {
    Write-Bad 'curl.exe is required for the speed test (ships with Windows 10 1803+).'
    return
  }

  $download = Measure-SpeedTransfer -Curl $curl -Mode 'download' -Seconds $Duration -Streams 4
  if ($download.Ok) {
    Write-Host ('  {0,-24} {1} Mbps  ({2} MB in {3}s)' -f 'Download', $download.Mbps, $download.MB, $download.Seconds)
    if ($download.Mirror -ne 'cloudflare') {
      $why = if ($download.Note) { $download.Note } else { 'no answer' }
      Write-Note "Cloudflare unavailable: $why; measured against the OVH mirror."
    }
  } elseif ($download.Note) {
    Write-Warn2 "download test failed: $($download.Note)"
  } else {
    Write-Warn2 'download test failed (every mirror unreachable)'
  }

  $upload = $null
  if (-not $NoUpload) {
    $upload = Measure-SpeedTransfer -Curl $curl -Mode 'upload' -Seconds $Duration -Streams 3
    if ($upload.Ok) {
      Write-Host ('  {0,-24} {1} Mbps  ({2} MB in {3}s)' -f 'Upload', $upload.Mbps, $upload.MB, $upload.Seconds)
    } elseif ($upload.Note) {
      Write-Warn2 "upload test failed: $($upload.Note)"
    } else {
      Write-Warn2 'upload test failed'
    }
    if (-not $upload.Ok) { $upload = $null }
  } else {
    Write-Note 'Upload skipped (-NoUpload).'
  }

  if ($download.Ok -and $download.Mirror -eq 'cloudflare' -and $upload -and $upload.Mbps -gt 0) {
    $ratio = [math]::Round($download.Mbps / $upload.Mbps, 1)
    if ($ratio -ge 5) { Write-Note "Download is ${ratio}x upload. Typical for home fibre/cable." }
    elseif ($ratio -ge 2) { Write-Note "Download is ${ratio}x upload." }
    else { Write-Note "Download is ${ratio}x upload: effectively a symmetric link." }
  }

  if ($Csv) {
    $rows = @(
      [pscustomobject][ordered]@{ metric = 'latency_avg'; value = $latency.Avg; unit = 'ms' }
      [pscustomobject][ordered]@{ metric = 'latency_jitter'; value = $latency.Jitter; unit = 'ms' }
      [pscustomobject][ordered]@{ metric = 'latency_loss'; value = $latency.Loss; unit = '%' }
    )
    if ($download.Ok) { $rows += [pscustomobject][ordered]@{ metric = 'download_avg'; value = $download.Mbps; unit = 'mbps' } }
    if ($upload -and $upload.Ok) { $rows += [pscustomobject][ordered]@{ metric = 'upload_avg'; value = $upload.Mbps; unit = 'mbps' } }
    try {
      $csvParams = @{ Path = $Csv; Encoding = 'UTF8' }
      if ($PSVersionTable.PSVersion.Major -lt 6) { $csvParams['NoTypeInformation'] = $true }
      $rows | Export-Csv @csvParams
      Write-Host "  Results saved to $Csv" -ForegroundColor Cyan
    } catch {
      Write-Warn2 "could not write CSV to $Csv"
    }
  }

  Write-Note 'Run it twice; Wi-Fi and background traffic move the numbers. Compare with: .\dns-bench.ps1 speed -Quick'
}

function Invoke-Status {
  Write-Host ("dns-bench {0}" -f $script:Version) -ForegroundColor White
  $adapter = Get-ActiveAdapter
  Write-Kv 'Adapter' $(if ($adapter) { "$($adapter.Name) ($($adapter.Status))" } else { 'none' })
  Write-Kv 'DNS source' (Get-DnsMode)
  Write-Kv 'DNS in use' (((Get-SystemDns) -join ', '))
  Write-Kv 'Script' $script:SelfPath
  Write-Kv 'Update URL' $script:UpdateUrl
  $file = Join-Path $HOME '.dns-bench-previous.txt'
  if (Test-Path $file) { Write-Kv 'Change history' $file }
}

function Invoke-Test {
  $target = if ($Argument) { $Argument } else { $Domain }
  if (-not $target) { Write-Bad 'usage: .\dns-bench.ps1 test DOMAIN'; return }
  $target = $target.TrimEnd('.')
  if ($target -notmatch '^[A-Za-z0-9._-]+$') { Write-Bad 'invalid domain'; return }
  Write-Section "Troubleshooting: $target"

  $servers = @(
    @('System resolver', $null),
    @('Cloudflare', '1.1.1.1'),
    @('Google', '8.8.8.8'),
    @('Quad9', '9.9.9.9'),
    @('OpenDNS', '208.67.222.222'),
    @('AdGuard (ads)', '94.140.14.14')
  )
  $gateway = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
    Sort-Object { $_.RouteMetric + $_.InterfaceMetric } | Select-Object -First 1).NextHop
  if ($gateway) { $servers += , @("Router ($gateway)", $gateway) }

  Write-Note '1) A record via each resolver'
  Write-Host ('  {0,-30} {1,-10} {2,8} {3,30}' -f 'Resolver', 'Status', 'Time', 'Answer') -ForegroundColor White
  $okSets = @{}
  $firstAnswers = @()
  $systemOk = $false
  foreach ($server in $servers) {
    $result = Resolve-Timed -Server $server[1] -Name $target -NoRetry
    $status = $result.Status
    if ($status -eq 'NOERROR' -and $result.Answers.Count -eq 0) { $status = 'NODATA' }
    if ($status -eq 'NOERROR' -and $result.Answers.Count -gt 0 -and $result.Answers[0] -match '^(0\.0\.0\.0|127\.|146\.112\.61\.)') { $status = 'BLOCKED' }
    $answerText = if ($result.Answers.Count -gt 0) { ($result.Answers[0..([math]::Min(2, $result.Answers.Count - 1))] -join ', ') } else { '-' }
    $color = if ($status -eq 'NOERROR') { 'Green' } elseif ($status -in @('NODATA', 'BLOCKED')) { 'Yellow' } else { 'Red' }
    Write-Host ('  {0,-30} {1,-10} {2,8} {3,30}' -f $server[0], $status, "$($result.Ms) ms", $answerText) -ForegroundColor $color
    if ($status -eq 'NOERROR') {
      if ($server[0] -eq 'System resolver') { $systemOk = $true }
      $key = ($result.Answers -join ',')
      if (-not $okSets.ContainsKey($key)) { $okSets[$key] = @() }
      $okSets[$key] += $server[0]
      if ($firstAnswers.Count -eq 0) { $firstAnswers = $result.Answers }
    }
  }

  Write-Host ''
  Write-Note '2) records'
  foreach ($type in @('A', 'AAAA', 'CNAME', 'NS', 'MX', 'TXT', 'SOA', 'CAA')) {
    try {
      $records = Resolve-DnsName -Name $target -Type $type -DnsOnly -QuickTimeout -ErrorAction Stop
      $values = @()
      foreach ($record in $records) {
        if ($type -eq 'A' -or $type -eq 'AAAA') { $values += $record.IPAddress }
        elseif ($type -eq 'MX') { $values += ("{0} {1}" -f $record.Preference, $record.NameExchange) }
        elseif ($type -eq 'NS') { $values += $record.NameHost }
        elseif ($type -eq 'CNAME') { $values += $record.NameHost }
        elseif ($type -eq 'TXT') { $values += ($record.Strings -join ' ') }
        elseif ($type -eq 'SOA') { $values += ("{0} serial {1}" -f $record.PrimaryServer, $record.SerialNumber) }
        elseif ($type -eq 'CAA') { $values += ("{0} {1} {2}" -f $record.Flags, $record.Tag, $record.Value) }
      }
      $values = @($values | Where-Object { $_ } | Select-Object -Unique)
      Write-Host ('  {0,-6} {1}' -f $type, $(if ($values.Count) { $values[0] } else { '-' }))
      foreach ($extra in ($values | Select-Object -Skip 1 | Select-Object -First 3)) {
        Write-Host ('  {0,-6} {1}' -f '', $extra)
      }
    } catch {
      Write-Host ('  {0,-6} -' -f $type) -ForegroundColor DarkGray
    }
  }

  Write-Host ''
  Write-Note '3) DNSSEC'
  try {
    $ds = Resolve-DnsName -Name $target -Type DS -Server '1.1.1.1' -DnsOnly -QuickTimeout -ErrorAction Stop
    Write-Kv 'Zone signed (DS record)' $(if ($ds) { 'yes' } else { 'no' })
  } catch {
    Write-Kv 'Zone signed (DS record)' 'no'
  }

  Write-Host ''
  Write-Note '4) reachability'
  $tested = 0
  foreach ($ip in ($firstAnswers | Select-Object -First 3)) {
    $tested++
    $p443 = Test-TcpPort -Target $ip -Port 443
    $p80 = Test-TcpPort -Target $ip -Port 80
    Write-Host ('  {0,-40} 443: {1,-12} 80: {2}' -f $ip,
      $(if ($null -ne $p443) { "$p443 ms" } else { 'fail' }),
      $(if ($null -ne $p80) { "$p80 ms" } else { 'fail' }))
  }
  if ($tested -eq 0) { Write-Note 'no addresses to test' }
  try {
    $response = Invoke-WebRequest -Uri "https://$target/" -UseBasicParsing -TimeoutSec 8 -MaximumRedirection 3
    Write-Kv 'HTTPS (system resolver)' ("HTTP {0}" -f $response.StatusCode)
  } catch {
    Write-Kv 'HTTPS (system resolver)' ("failed: {0}" -f $_.Exception.Message)
  }

  Write-Section 'Verdict'
  $problems = @()
  if (-not $systemOk) { $problems += 'Your system resolver failed while public resolvers answered: the problem is local DNS (router/ISP/VPN/filter). Try: .\dns-bench.ps1 set cloudflare' }
  if ($okSets.Keys.Count -gt 1) { $problems += 'Resolvers return different address sets (normal for CDNs/geo-DNS; suspicious for a single-host site).' }
  if ($problems.Count -eq 0) { Write-Good '  Nothing wrong found.' }
  else { foreach ($problem in $problems) { Write-Host "  - $problem" } }
}

function Invoke-Update {
  $url = $script:UpdateUrl
  if (-not $url) { Write-Bad 'no update URL set (edit $script:UpdateUrl or set DNSBENCH_UPDATE_URL)'; return }
  Write-Host "Fetching $url"
  $tempFile = Join-Path $script:TmpDir 'dns-bench.remote.ps1'
  try {
    Invoke-WebRequest -Uri $url -UseBasicParsing -OutFile $tempFile -TimeoutSec 30
  } catch {
    Write-Bad "download failed: $($_.Exception.Message)"
    return
  }
  $content = Get-Content -Path $tempFile -Raw
  if (-not $content -or $content.Length -lt 2000) { Write-Bad 'downloaded file is too small to be dns-bench'; return }
  if ($content -notmatch 'dns-bench') { Write-Bad 'downloaded file does not look like dns-bench (check the URL)'; return }
  if ($content -notmatch 'param\s*\(') { Write-Bad 'downloaded file is not a PowerShell script (check the URL)'; return }

  $match = [regex]::Match($content, '(?m)^\$script:Version\s*=\s*''([0-9][0-9.]*)''')
  $remoteVersion = if ($match.Success) { $match.Groups[1].Value } else { 'unknown' }

  if ($Check) {
    Write-Kv 'installed' $script:Version
    Write-Kv 'remote' $remoteVersion
    if ($remoteVersion -eq $script:Version) { Write-Good '  up to date' } else { Write-Host '  update available: .\dns-bench.ps1 update' -ForegroundColor Yellow }
    return
  }
  if ($remoteVersion -eq $script:Version -and -not $Force) {
    Write-Host "Already up to date ($($script:Version)). Use -Force to reinstall anyway."
    return
  }

  $backup = "$($script:SelfPath).$($script:Version).bak"
  Copy-Item -Path $script:SelfPath -Destination $backup -Force -ErrorAction SilentlyContinue
  if (Test-Path $backup) { Write-Kv 'backup' $backup }
  try {
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($script:SelfPath, $content, $utf8)
    Write-Host ("  updated: {0} -> {1}" -f $script:Version, $remoteVersion)
    Write-Host "Done. Restart dns-bench to use $remoteVersion."
  } catch {
    Write-Bad "could not write $($script:SelfPath): $($_.Exception.Message)"
  }
}

function Invoke-Flush {
  if (-not $script:OnWindows) {
    Write-Note 'The flush command is Windows-only (Clear-DnsClientCache + ipconfig /flushdns).'
    Write-Note 'Nothing was changed. Use dns-bench.zsh on macOS or Linux for the equivalent commands.'
    return
  }
  Write-Section 'Flush DNS cache'
  $ok = $false
  try {
    Clear-DnsClientCache -ErrorAction Stop
    $ok = $true
    Write-Kv 'Clear-DnsClientCache' 'ok'
  } catch {
    Write-Kv 'Clear-DnsClientCache' ("failed: " + $_.Exception.Message)
  }
  try {
    & ipconfig /flushdns 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
      $ok = $true
      Write-Kv 'ipconfig /flushdns' 'ok'
    } else {
      Write-Kv 'ipconfig /flushdns' ("exit code $LASTEXITCODE (ignored)")
    }
  } catch {
    Write-Kv 'ipconfig /flushdns' ("failed: " + $_.Exception.Message + " (ignored)")
  }
  if ($ok) { Write-Host '  DNS cache flushed.' -ForegroundColor Green }
}

function Invoke-Demo {
  $demoRows = @(
    [pscustomobject]@{ Index = 1; Name = 'Cloudflare'; Region = 'GL'; Kind = 'U'; Cached = '14 ms'; Jitter = '1.2 ms'; Loss = 0; Cold = '31 ms'; Score = '22.0'; V4Ping = '12.4 ms'; V6Dns = '15 ms'; V6Ping = '12.8 ms'; Dnssec = 'yes'; Nx = 'ok'; Tcp = 'yes'; Dot = 'yes'; Doh = 'yes'; Ads = 'no'; Pop = 'ams' }
    [pscustomobject]@{ Index = 4; Name = 'Google Public DNS'; Region = 'GL'; Kind = 'U'; Cached = '16 ms'; Jitter = '1.8 ms'; Loss = 0; Cold = '34 ms'; Score = '24.7'; V4Ping = '13.1 ms'; V6Dns = '17 ms'; V6Ping = '13.5 ms'; Dnssec = 'yes'; Nx = 'ok'; Tcp = 'yes'; Dot = 'yes'; Doh = 'yes'; Ads = 'no'; Pop = 'ams01' }
    [pscustomobject]@{ Index = 6; Name = 'Quad9 (Unfiltered)'; Region = 'GL'; Kind = 'U'; Cached = '18 ms'; Jitter = '2.1 ms'; Loss = 0; Cold = '38 ms'; Score = '27.3'; V4Ping = '14.6 ms'; V6Dns = '19 ms'; V6Ping = '14.9 ms'; Dnssec = 'yes'; Nx = 'ok'; Tcp = 'yes'; Dot = 'yes'; Doh = 'yes'; Ads = 'no'; Pop = 'fra' }
    [pscustomobject]@{ Index = 12; Name = 'AdGuard Unfiltered'; Region = 'GL'; Kind = 'U'; Cached = '21 ms'; Jitter = '2.6 ms'; Loss = 0; Cold = '44 ms'; Score = '31.7'; V4Ping = '15.2 ms'; V6Dns = '22 ms'; V6Ping = '15.6 ms'; Dnssec = 'yes'; Nx = 'ok'; Tcp = 'yes'; Dot = 'yes'; Doh = 'yes'; Ads = 'no'; Pop = 'ams' }
    [pscustomobject]@{ Index = 13; Name = 'Control D Unfiltered'; Region = 'GL'; Kind = 'U'; Cached = '23 ms'; Jitter = '3.0 ms'; Loss = 0; Cold = '47 ms'; Score = '34.3'; V4Ping = '16.8 ms'; V6Dns = '24 ms'; V6Ping = '17.1 ms'; Dnssec = 'yes'; Nx = 'ok'; Tcp = 'yes'; Dot = 'yes'; Doh = 'yes'; Ads = 'no'; Pop = 'ams' }
    [pscustomobject]@{ Index = 16; Name = 'NextDNS (Anycast)'; Region = 'GL'; Kind = 'U'; Cached = '27 ms'; Jitter = '3.4 ms'; Loss = 0; Cold = '52 ms'; Score = '38.7'; V4Ping = '17.9 ms'; V6Dns = '28 ms'; V6Ping = '18.2 ms'; Dnssec = 'yes'; Nx = 'ok'; Tcp = 'yes'; Dot = 'yes'; Doh = 'yes'; Ads = 'no'; Pop = 'ams' }
    [pscustomobject]@{ Index = 24; Name = 'Verisign Public DNS'; Region = 'GL'; Kind = 'U'; Cached = '31 ms'; Jitter = '4.1 ms'; Loss = 0; Cold = '58 ms'; Score = '43.7'; V4Ping = '19.4 ms'; V6Dns = '31 ms'; V6Ping = '19.8 ms'; Dnssec = 'yes'; Nx = 'ok'; Tcp = 'yes'; Dot = 'no'; Doh = 'yes'; Ads = 'no'; Pop = '-' }
    [pscustomobject]@{ Index = 52; Name = 'Router / Gateway'; Region = 'LAN'; Kind = 'C'; Cached = '2.4 ms'; Jitter = '0.6 ms'; Loss = 0; Cold = '39 ms'; Score = '68.8'; V4Ping = '1.9 ms'; V6Dns = '-'; V6Ping = '1.8 ms'; Dnssec = 'yes'; Nx = 'ok'; Tcp = 'yes'; Dot = 'no'; Doh = 'yes'; Ads = 'no'; Pop = '-' }
    [pscustomobject]@{ Index = 53; Name = 'Current system DNS'; Region = 'LAN'; Kind = 'C'; Cached = '14 ms'; Jitter = '1.5 ms'; Loss = 0; Cold = '36 ms'; Score = '23.0'; V4Ping = '12.6 ms'; V6Dns = '15 ms'; V6Ping = '12.9 ms'; Dnssec = 'yes'; Nx = 'ok'; Tcp = 'yes'; Dot = 'no'; Doh = 'yes'; Ads = 'no'; Pop = '-' }
  )

  Write-Host ("dns-bench {0}  {1}  |  target: {2}  |  samples: {3}" -f $script:Version,
    (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Domain, $Samples) -ForegroundColor White

  Write-Section 'Network'
  Write-Kv 'Host' 'DEMO-PC | Windows 11 24H2 | AMD64'
  Write-Kv 'Active adapter' 'Wi-Fi (Intel Wi-Fi 6E AX211)'
  Write-Kv 'Link speed' '866 Mbps'
  Write-Kv 'MAC / MTU' '02-00-00-00-00-01 / 1500'
  Write-Kv 'Local IPv4' '192.0.2.42'
  Write-Kv 'Local IPv6' '2001:db8:4::42'
  Write-Kv 'Gateway' '192.0.2.1'
  Write-Kv 'Gateway latency' '3.1 ms, loss 0%'
  Write-Kv 'System proxy' 'Off'
  Write-Kv 'VPN connected' 'Off'
  Write-Kv 'System DNS (in use)' '1.1.1.1, 1.0.0.1'
  Write-Kv 'DNS source' 'Automatic (DHCP / router)'
  Write-Kv 'IPv6 connectivity' 'Working'
  Write-Kv 'Public IPv4' '203.0.113.42'
  Write-Kv 'Public IPv6' '2001:db8:4::42'
  Write-Kv 'Nearest Cloudflare PoP' 'AMS (WARP: off)'
  Write-Kv 'Location' 'Amsterdam, North Holland, Netherlands'
  Write-Kv 'ISP / ASN' 'Example ISP (AS64500)'
  Write-Kv 'Time zone' 'Europe/Amsterdam'
  Write-Kv 'DNS interception' 'Clear'
  Write-Kv 'Captive portal' 'None'
  Write-Kv 'System resolver egress IP' '203.0.113.42'

  Write-Section ("DNS benchmark: {0} resolvers" -f 53)
  Write-Note ('Cached = median of {0} queries for {1} | Cold = median of 3 random uncached names | Score = (cached + 2*cold)/3 + 3*loss%' -f $Samples, $Domain)
  $script:Results = @($demoRows)
  Show-Table

  if (-not $SkipGeo) {
    Write-Section 'Latency to each continent (TCP connect, median of 3)'
    $demoGeo = @(
      @('North America', 'N. Virginia', 'us-east-1', 82), @('North America', 'Oregon', 'us-west-2', 145),
      @('North America', 'Montreal', 'ca-central-1', 78), @('South America', 'Sao Paulo', 'sa-east-1', 187),
      @('Europe', 'Ireland', 'eu-west-1', 18), @('Europe', 'Frankfurt', 'eu-central-1', 11),
      @('Europe', 'Stockholm', 'eu-north-1', 24), @('Middle East', 'Bahrain', 'me-south-1', 112),
      @('Middle East', 'UAE', 'me-central-1', 118), @('Africa', 'Cape Town', 'af-south-1', 168),
      @('Asia', 'Mumbai', 'ap-south-1', 118), @('Asia', 'Hyderabad', 'ap-south-2', 121),
      @('Asia', 'Singapore', 'ap-southeast-1', 165), @('Asia', 'Hong Kong', 'ap-east-1', 192),
      @('Asia', 'Tokyo', 'ap-northeast-1', 238), @('Oceania', 'Sydney', 'ap-southeast-2', 285)
    )
    foreach ($region in $demoGeo) {
      $blocks = [int]([math]::Min(30, $region[3] / 12))
      Write-Host ('  {0,-16} {1,-14} {2,-16} {3,8} {4}' -f $region[0], $region[1], $region[2], "$($region[3]) ms", ('#' * $blocks))
    }
    Write-Note 'Closest cloud region: Frankfurt (Europe) at 11 ms. Region latency is physical distance, it does not depend on your DNS choice.'
  }

  if (-not $SkipServices) {
    Write-Section ("Popular services: edge RTT returned by each resolver ({0} services x {1} resolvers)" -f 8, 5)
    Write-Note 'Each value = TCP connect time to the IP that resolver handed back. Lower = closer CDN edge.'
    $demoServices = @(
      @('Google', 12, 13, 14, 16, 18), @('YouTube', 14, 15, 17, 19, 21),
      @('Netflix', 18, 19, 21, 24, 27), @('Spotify', 20, 21, 23, 26, 29),
      @('GitHub', 24, 25, 27, 31, 34), @('Microsoft', 22, 23, 25, 28, 31),
      @('AWS S3', 26, 28, 30, 34, 37), @('Steam', 29, 31, 33, 37, 41)
    )
    foreach ($service in $demoServices) {
      $line = '  {0,-20}' -f $service[0]
      for ($i = 1; $i -le 5; $i++) { $line += ('{0,9}' -f "$($service[$i]) ms") }
      Write-Host $line
    }
    Write-Host ''
    Write-Host ('  {0,-26} {1,14} {2,12} {3,13} {4,8}' -f 'Resolver summary', 'Avg edge RTT', 'Avg lookup', 'Best-in-row', 'Failed') -ForegroundColor White
    $demoSummary = @(
      @('Cloudflare', 20, 13, '8/8'), @('Google Public DNS', 22, 15, '0/8'),
      @('Quad9 (Unfiltered)', 25, 17, '0/8'), @('AdGuard Unfiltered', 28, 20, '0/8'),
      @('NextDNS (Anycast)', 31, 23, '0/8')
    )
    foreach ($entry in $demoSummary) {
      Write-Host ('  {0,-26} {1,14} {2,12} {3,13} {4,8}' -f $entry[0], "$($entry[1]) ms", "$($entry[2]) ms", $entry[3], 0)
    }
  }

  Write-Section 'Speed test'
  Write-Note 'Cloudflare edge (OVH fallback), 4 parallel streams, IPv4. Measures the link itself, not your DNS choice.'
  Write-Host ('  {0,-24} {1} ms   (jitter {2} ms, {3}% loss)' -f 'Latency to 1.1.1.1', '14.2', '1.1', 0)
  Write-Host ('  {0,-24} {1} Mbps  ({2} MB in {3}s)' -f 'Download', '482.6', '241', '4.0')
  Write-Host ('  {0,-24} {1} Mbps  ({2} MB in {3}s)' -f 'Upload', '211.4', '84', '3.2')
  Write-Note 'Download is 2.3x upload.'

  Write-Section 'Summary'
  Write-Kv 'Fastest DNS (unfiltered)' '#1 Cloudflare: cached 14 ms, score 22.0'
  Write-Kv 'Your current DNS' 'Current system DNS: cached 14 ms, cold 36 ms, score 23.0'
  Write-Kv '' 'already near the top'
  Write-Note 'Demo data. Nothing was probed and no DNS settings were read.'
}

# =====================================================================
# external tool helpers (3.3 network commands)
# =====================================================================
function Get-NullDevice {
  if ($script:OnWindows) { return 'NUL' }
  return '/dev/null'
}

function Get-BinPath {
  param([string[]]$Names)
  foreach ($name in $Names) {
    $found = Get-Command $name -ErrorAction SilentlyContinue
    if ($found -and $found.CommandType -eq 'Application') {
      if ($found.Source) { return $found.Source }
      if ($found.Path) { return $found.Path }
    }
  }
  return $null
}

# Bounded, non-interactive external call. Every argument is quoted; the
# caller owns the per-tool timeout (-m, +time=, -w) as well as WallClock here.
function Invoke-External {
  param(
    [string]$File,
    [string[]]$Arguments = @(),
    [int]$TimeoutSec = 20,
    [string]$InputText
  )
  $result = [pscustomobject]@{ Ok = $false; TimedOut = $false; ExitCode = -1; Output = ''; Error = '' }
  if (-not $File) { $result.Error = 'binary not found'; return $result }
  $process = $null
  try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $File
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $quoted = @()
    foreach ($argument in $Arguments) {
      $quoted += ('"' + ([string]$argument).Replace('"', '\"') + '"')
    }
    $psi.Arguments = ($quoted -join ' ')
    if ($PSBoundParameters.ContainsKey('InputText')) { $psi.RedirectStandardInput = $true }
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    [void]$process.Start()
    if ($psi.RedirectStandardInput) {
      $process.StandardInput.Write([string]$InputText)
      $process.StandardInput.Close()
    }
    $outTask = $process.StandardOutput.ReadToEndAsync()
    $errTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutSec * 1000)) {
      try {
        $process.Kill()
        [void]$process.WaitForExit(1000)
      } catch { }
      $result.TimedOut = $true
      $result.Error = "timed out after ${TimeoutSec}s"
      return $result
    }
    $result.Output = $outTask.Result
    $result.Error = $errTask.Result
    $result.ExitCode = $process.ExitCode
    $result.Ok = ($process.ExitCode -eq 0)
    return $result
  } catch {
    $result.Error = $_.Exception.Message
    return $result
  } finally {
    if ($process) { $process.Dispose() }
  }
}

function Resolve-AllAddresses {
  param([string]$Name)
  if (-not $Name) { return @() }
  if ($Name -match '^(\d{1,3}\.){3}\d{1,3}$' -or $Name -match ':') { return @($Name) }
  $found = @()
  if (Get-Command Resolve-DnsName -ErrorAction SilentlyContinue) {
    try {
      $records = Resolve-DnsName -Name $Name -Type A -DnsOnly -QuickTimeout -ErrorAction Stop
      foreach ($record in $records) { if ($record.IPAddress) { $found += $record.IPAddress } }
    } catch { }
  }
  if ($found.Count -eq 0) {
    $dig = Get-BinPath @('dig')
    if ($dig) {
      $result = Invoke-External -File $dig -Arguments @('+short', '+time=2', '+tries=1', 'A', $Name) -TimeoutSec 6
      foreach ($line in ($result.Output -split "`n")) {
        if ($line -match '^(\d{1,3}\.){3}\d{1,3}$') { $found += $line.Trim() }
      }
    }
  }
  return @($found | Select-Object -Unique)
}

function Resolve-FirstAddress {
  param([string]$Name)
  $all = @(Resolve-AllAddresses $Name)
  if ($all.Count -gt 0) { return $all[0] }
  return $null
}

function Get-TxtRecords {
  param([string]$Name, [string]$Server)
  $values = @()
  if (Get-Command Resolve-DnsName -ErrorAction SilentlyContinue) {
    try {
      $query = @{ Name = $Name; Type = 'TXT'; DnsOnly = $true; QuickTimeout = $true; ErrorAction = 'Stop' }
      if ($Server) { $query['Server'] = $Server }
      $records = Resolve-DnsName @query
      foreach ($record in $records) {
        if ($record.Strings) { $values += ($record.Strings -join '') }
      }
      if ($values.Count -gt 0) { return $values }
    } catch { }
  }
  $dig = Get-BinPath @('dig')
  if ($dig) {
    $arguments = @('+short', '+time=2', '+tries=1', 'TXT', $Name)
    if ($Server) { $arguments += ('@' + $Server) }
    $result = Invoke-External -File $dig -Arguments $arguments -TimeoutSec 6
    if ($result.Ok) {
      foreach ($line in ($result.Output -split "`n")) {
        $value = $line.Trim().Trim('"')
        if ($value) { $values += $value }
      }
    }
  }
  return $values
}

function Get-PublicIp {
  $curl = Get-CurlExe
  if ($curl) {
    $result = Invoke-External -File $curl -Arguments @('-4', '-sS', '--max-time', '5', '--url', 'https://1.1.1.1/cdn-cgi/trace') -TimeoutSec 8
    if ($result.Ok) {
      foreach ($line in ($result.Output -split "`n")) {
        if ($line -match '^ip=(\S+)') { return $matches[1] }
      }
    }
  }
  if (Get-Command Resolve-DnsName -ErrorAction SilentlyContinue) {
    try {
      $records = Resolve-DnsName -Name 'myip.opendns.com' -Type A -Server '208.67.222.222' -DnsOnly -QuickTimeout -ErrorAction Stop
      $address = ($records | Where-Object { $_.IPAddress } | Select-Object -First 1).IPAddress
      if ($address) { return $address }
    } catch { }
  }
  $dig = Get-BinPath @('dig')
  if ($dig) {
    $result = Invoke-External -File $dig -Arguments @('+short', '+time=2', '+tries=1', 'myip.opendns.com', 'A', '@resolver1.opendns.com') -TimeoutSec 6
    foreach ($line in ($result.Output -split "`n")) {
      if ($line -match '^(\d{1,3}\.){3}\d{1,3}$') { return $line.Trim() }
    }
  }
  return $null
}

function Get-ReverseName {
  param([string]$Address)
  if ($Address -match '^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$') {
    return ('{0}.{1}.{2}.{3}.in-addr.arpa' -f $matches[4], $matches[3], $matches[2], $matches[1])
  }
  $parsed = $null
  try { $parsed = [System.Net.IPAddress]::Parse($Address) } catch { return $null }
  if (-not $parsed -or $parsed.AddressFamily -ne 'InterNetworkV6') { return $null }
  $bytes = $parsed.GetAddressBytes()
  $builder = New-Object System.Text.StringBuilder
  for ($i = $bytes.Length - 1; $i -ge 0; $i--) {
    [void]$builder.Append(('{0:x2}' -f $bytes[$i]))
    [void]$builder.Append('.')
  }
  [void]$builder.Append('ip6.arpa')
  return $builder.ToString()
}

function Get-RecordValues {
  param([string]$Server, [string]$Name, [string]$Type = 'A')
  $values = @()
  $status = 'ERROR'
  if (Get-Command Resolve-DnsName -ErrorAction SilentlyContinue) {
    try {
      $query = @{ Name = $Name; Type = $Type; Server = $Server; DnsOnly = $true; QuickTimeout = $true; ErrorAction = 'Stop' }
      $records = Resolve-DnsName @query
      $status = 'NOERROR'
      foreach ($record in $records) {
        switch ($Type.ToUpper()) {
          'A' { if ($record.IPAddress) { $values += $record.IPAddress } }
          'AAAA' { if ($record.IPAddress) { $values += $record.IPAddress } }
          'CNAME' { if ($record.NameHost) { $values += $record.NameHost } }
          'NS' { if ($record.NameHost) { $values += $record.NameHost } }
          'MX' { if ($record.NameExchange) { $values += ('{0} {1}' -f $record.Preference, $record.NameExchange) } }
          'TXT' { if ($record.Strings) { $values += ($record.Strings -join '') } }
          'CAA' { if ($record.Tag) { $values += ('{0} {1} {2}' -f $record.Flags, $record.Tag, $record.Value) } }
          'SOA' { if ($record.PrimaryServer) { $values += ('{0} serial {1}' -f $record.PrimaryServer, $record.SerialNumber) } }
          default { if ($record.IPAddress) { $values += $record.IPAddress } }
        }
      }
    } catch {
      $message = "$($_.Exception.Message) $($_.FullyQualifiedErrorId)"
      if ($message -match 'does not exist|NXDOMAIN|NAME_ERROR') { $status = 'NXDOMAIN' }
      elseif ($message -match 'server failure|SERVFAIL') { $status = 'SERVFAIL' }
      elseif ($message -match 'refused|REFUSED') { $status = 'REFUSED' }
      elseif ($message -match 'timed out|timeout|no response|unreachable') { $status = 'TIMEOUT' }
      else { $status = 'ERROR' }
    }
  } else {
    $dig = Get-BinPath @('dig')
    if (-not $dig) { return [pscustomobject]@{ Status = 'NO-TOOL'; Values = @() } }
    $result = Invoke-External -File $dig -Arguments @('+short', '+time=2', '+tries=1', ('@' + $Server), $Name, $Type) -TimeoutSec 6
    if ($result.TimedOut) { $status = 'TIMEOUT' }
    elseif ($result.ExitCode -ne 0) { $status = 'ERROR' }
    else {
      $status = 'NOERROR'
      foreach ($line in ($result.Output -split "`n")) {
        $value = $line.Trim()
        if ($value) { $values += $value }
      }
    }
  }
  return [pscustomobject]@{
    Status = $status
    Values = @($values | Where-Object { $_ } | Select-Object -Unique)
  }
}

function Get-ConfiguredDns {
  $servers = @()
  if (Get-Command Get-DnsClientServerAddress -ErrorAction SilentlyContinue) {
    try { $servers = @(Get-SystemDns) } catch { }
  }
  if ($servers.Count -eq 0 -and $script:OSKind -eq 'macos') {
    $scutil = Get-BinPath @('scutil')
    if ($scutil) {
      $result = Invoke-External -File $scutil -Arguments @('--dns') -TimeoutSec 5
      foreach ($line in ($result.Output -split "`n")) {
        if ($line -match 'nameserver\[[0-9]+\]\s*:\s*(\S+)') { $servers += $matches[1] }
      }
    }
  }
  if ($servers.Count -eq 0 -and (Test-Path '/etc/resolv.conf')) {
    foreach ($line in (Get-Content -Path '/etc/resolv.conf' -ErrorAction SilentlyContinue)) {
      if ($line -match '^\s*nameserver\s+(\S+)') { $servers += $matches[1] }
    }
  }
  $unique = @()
  foreach ($server in $servers) {
    if ($server -and $unique -notcontains $server) { $unique += $server }
  }
  return $unique
}

function Test-SameAddress {
  param([string]$A, [string]$B)
  if ($A -eq $B) { return $true }
  try {
    $first = [System.Net.IPAddress]::Parse($A)
    $second = [System.Net.IPAddress]::Parse($B)
    return $first.Equals($second)
  } catch {
    return $false
  }
}

function ConvertFrom-CertDate {
  param([string]$Text)
  if (-not $Text -or $Text -eq '-') { return $null }
  $clean = ($Text -replace '\s+', ' ').Trim()
  foreach ($format in @('MMM d HH:mm:ss yyyy GMT', 'MMM d HH:mm:ss yyyy')) {
    try {
      return [datetime]::ParseExact($clean, $format, [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AdjustToUniversal)
    } catch { }
  }
  try {
    return [datetime]::Parse($clean, [Globalization.CultureInfo]::InvariantCulture,
      [Globalization.DateTimeStyles]::AdjustToUniversal)
  } catch {
    return $null
  }
}

function Test-DfPing {
  param([string]$PingExe, [string]$Target, [int]$Payload, [int]$TimeoutSec = 3)
  $arguments = @()
  if ($script:OnWindows) {
    $arguments = @('-4', '-n', '1', '-w', '1000', '-f', '-l', "$Payload", $Target)
  } elseif ($script:OSKind -eq 'macos') {
    $arguments = @('-D', '-c', '1', '-W', '1000', '-s', "$Payload", $Target)
  } else {
    $arguments = @('-M', 'do', '-c', '1', '-W', '1', '-s', "$Payload", $Target)
  }
  $result = Invoke-External -File $PingExe -Arguments $arguments -TimeoutSec $TimeoutSec
  if ($result.TimedOut -or $result.ExitCode -ne 0) { return $false }
  $text = "$($result.Output) $($result.Error)"
  if ($text -match 'too long|too big|fragmentation needed|needs to be fragmented|Message too long') { return $false }
  return $true
}

function ConvertFrom-TraceText {
  param([string]$Text)
  $rows = @()
  foreach ($line in ($Text -split "`n")) {
    $clean = $line.TrimEnd()
    if ($clean -match 'pmtu|Trace complete|Tracing route|over a maximum') { continue }
    if ($clean -match '^\s*(\d+)[\s:?]+\s*(.*)$') {
      $hop = [int]$matches[1]
      $rest = $matches[2]
      $address = '*'
      if ($rest -match '\b(\d{1,3}(?:\.\d{1,3}){3})\b') { $address = $matches[1] }
      elseif ($rest -match '\b([0-9a-fA-F]{0,4}(?::[0-9a-fA-F]{0,4}){2,})\b') { $address = $matches[1] }
      $rtt = '-'
      if ($rest -match '<?\s*([\d.]+)\s*ms') { $rtt = "$($matches[1]) ms" }
      $rows += [pscustomobject]@{ Hop = $hop; Address = $address; Rtt = $rtt }
    }
  }
  return $rows
}

function Get-PortState {
  param([string]$Target, [int]$Port, [int]$TimeoutMs = 2000)
  $client = New-Object System.Net.Sockets.TcpClient
  $watch = [System.Diagnostics.Stopwatch]::StartNew()
  try {
    $task = $client.ConnectAsync($Target, $Port)
    if (-not $task.Wait($TimeoutMs)) { return [pscustomobject]@{ State = 'filtered'; Ms = $null } }
    $watch.Stop()
    if ($client.Connected) { return [pscustomobject]@{ State = 'open'; Ms = [int]$watch.ElapsedMilliseconds } }
    return [pscustomobject]@{ State = 'closed'; Ms = $null }
  } catch {
    $inner = $_.Exception
    if ($inner.InnerException) { $inner = $inner.InnerException }
    $socket = $inner -as [System.Net.Sockets.SocketException]
    if ($socket -and $socket.SocketErrorCode -eq 'ConnectionRefused') {
      return [pscustomobject]@{ State = 'closed'; Ms = $null }
    }
    if ($socket -and ($socket.SocketErrorCode -eq 'TimedOut' -or
        $socket.SocketErrorCode -eq 'HostUnreachable' -or
        $socket.SocketErrorCode -eq 'NetworkUnreachable')) {
      return [pscustomobject]@{ State = 'filtered'; Ms = $null }
    }
    return [pscustomobject]@{ State = 'closed'; Ms = $null }
  } finally {
    $client.Close()
  }
}

# =====================================================================
# network commands (3.3)
# =====================================================================
function Invoke-Ports {
  if (-not $Argument) {
    Write-Bad 'usage: .\dns-bench.ps1 ports HOST [PORTS]'
    return
  }
  $target = $Argument.Trim()
  $portText = ''
  if ($Rest -and $Rest.Count -gt 0) { $portText = ($Rest -join ' ') }
  if (-not $portText) { $portText = '22 53 80 443 853 3306 5432 6379 8080' }
  $ports = @()
  foreach ($token in ($portText -split '[,\s]+')) {
    if ($token -match '^\d+$') {
      $value = [int]$token
      if ($value -ge 1 -and $value -le 65535) { $ports += $value }
    }
  }
  $ports = @($ports | Select-Object -Unique)
  if ($ports.Count -eq 0) { Write-Bad 'no valid ports given'; return }

  $serviceNames = @{ 22 = 'ssh'; 53 = 'dns'; 80 = 'http'; 443 = 'https'; 853 = 'dot'; 3306 = 'mysql'
    5432 = 'postgres'; 6379 = 'redis'; 8080 = 'http-alt' }
  Write-Section ("TCP ports: $target")
  Write-Host ('  {0,-5} {1,-10} {2,-9} {3}' -f 'Port', 'State', 'Connect', 'Service') -ForegroundColor White
  $openCount = 0
  foreach ($port in $ports) {
    $probe = Get-PortState -Target $target -Port $port -TimeoutMs 2000
    $msText = '-'
    if ($null -ne $probe.Ms) { $msText = ("{0} ms" -f $probe.Ms) }
    $color = 'Gray'
    if ($probe.State -eq 'open') { $color = 'Green'; $openCount++ }
    elseif ($probe.State -eq 'filtered') { $color = 'Yellow' }
    $service = ''
    if ($serviceNames.ContainsKey($port)) { $service = $serviceNames[$port] }
    Write-Host ('  {0,-5} {1,-10} {2,-9} {3}' -f $port, $probe.State, $msText, $service) -ForegroundColor $color
  }
  Write-Note ("{0} of {1} open. open = handshake completed, closed = refused, filtered = no reply (drop/firewall)." -f $openCount, $ports.Count)
}

function Invoke-Http {
  if (-not $Argument) {
    Write-Bad 'usage: .\dns-bench.ps1 http URL'
    return
  }
  $url = $Argument.Trim()
  if ($url -notmatch '^[A-Za-z][A-Za-z0-9+.-]*://') { $url = 'https://' + $url }
  Write-Section "HTTP: $url"
  $curl = Get-CurlExe
  if (-not $curl) {
    Write-Bad 'http needs curl (curl.exe ships with Windows 10 1803+).'
    return
  }
  $template = '%{http_code}|%{time_namelookup}|%{time_connect}|%{time_appconnect}|%{time_starttransfer}|%{time_total}|%{size_download}|%{num_redirects}|%{url_effective}'
  $result = Invoke-External -File $curl -Arguments @('-sS', '-L', '--max-time', '20', '-o', (Get-NullDevice), '-w', $template, '--url', $url) -TimeoutSec 25
  if ($result.TimedOut) { Write-Bad 'request timed out'; return }
  $line = $null
  foreach ($candidate in ($result.Output -split "`n")) {
    if ($candidate -match '^\d{3}\|') { $line = $candidate.Trim() }
  }
  if (-not $line) {
    Write-Bad ("curl returned no timing data{0}" -f $(if ($result.Error) { ": $($result.Error.Trim())" } else { '' }))
    return
  }
  $fields = $line -split '\|'
  if ($fields.Count -lt 9) { Write-Bad 'could not parse curl timing output'; return }

  $dnsMs = [int][math]::Round([double]$fields[1] * 1000)
  $connectRaw = [double]$fields[2]
  $tlsRaw = [double]$fields[3]
  $ttfbRaw = [double]$fields[4]
  $connectMs = [int][math]::Round(($connectRaw - [double]$fields[1]) * 1000)
  $tlsMs = [int][math]::Round(($tlsRaw - $connectRaw) * 1000)
  $ttfbMs = [int][math]::Round(($ttfbRaw - $tlsRaw) * 1000)
  $totalMs = [int][math]::Round([double]$fields[5] * 1000)
  if ($connectMs -lt 0) { $connectMs = 0 }
  if ($tlsMs -lt 0) { $tlsMs = 0 }
  if ($ttfbMs -lt 0) { $ttfbMs = 0 }

  Write-Kv 'HTTP code' $fields[0]
  Write-Kv 'dns' ("{0} ms" -f $dnsMs)
  Write-Kv 'connect' ("{0} ms" -f $connectMs)
  Write-Kv 'tls' ("{0} ms" -f $tlsMs)
  Write-Kv 'ttfb' ("{0} ms" -f $ttfbMs)
  Write-Kv 'total' ("{0} ms" -f $totalMs)
  Write-Kv 'size' ("{0} bytes" -f [int64]$fields[6])
  Write-Kv 'redirects' $fields[7]
  Write-Kv 'final URL' $fields[8]
}

function Invoke-Tls {
  if (-not $Argument) {
    Write-Bad 'usage: .\dns-bench.ps1 tls HOST[:PORT]'
    return
  }
  $target = $Argument.Trim()
  $hostName = $target
  $port = 443
  if ($target -match '^\[(.+)\]:(\d+)$') {
    $hostName = $matches[1]
    $port = [int]$matches[2]
  } elseif ($target -match '^([^:]+):(\d+)$') {
    $hostName = $matches[1]
    $port = [int]$matches[2]
  }
  Write-Section ("TLS: {0}:{1}" -f $hostName, $port)

  $subject = $null
  $issuer = '-'
  $notBefore = '-'
  $notAfter = '-'
  $sanCount = 'n/a'
  $protocol = '-'
  $method = $null

  $openssl = Get-BinPath @('openssl')
  if ($openssl) {
    $handshake = Invoke-External -File $openssl `
      -Arguments @('s_client', '-connect', ("{0}:{1}" -f $hostName, $port), '-servername', $hostName, '-showcerts') `
      -TimeoutSec 15 -InputText ''
    $pem = @()
    $inPem = $false
    foreach ($line in ($handshake.Output -split "`n")) {
      if ($line -match 'BEGIN CERTIFICATE') { $inPem = $true }
      if ($inPem) { $pem += $line.TrimEnd() }
      if ($line -match 'END CERTIFICATE') { break }
    }
    if ($pem.Count -ge 2) {
      $method = 'openssl s_client'
      $certFile = Join-Path $script:TmpDir 'tls-cert.pem'
      try { Set-Content -Path $certFile -Value $pem -Encoding ASCII } catch { }
      $details = Invoke-External -File $openssl `
        -Arguments @('x509', '-in', $certFile, '-noout', '-subject', '-issuer', '-startdate', '-enddate') -TimeoutSec 10
      if ($details.Output -match '(?m)^issuer=\s*(.+)$') { $issuer = $matches[1].Trim() }
      if ($details.Output -match '(?m)^notBefore=\s*(.+)$') { $notBefore = $matches[1].Trim() }
      if ($details.Output -match '(?m)^notAfter=\s*(.+)$') { $notAfter = $matches[1].Trim() }
      if ($details.Output -match 'subject=.*?CN\s*=\s*([^,\r\n]+)') { $subject = $matches[1].Trim() }
      elseif ($details.Output -match '(?m)^subject=\s*(.+)$') { $subject = $matches[1].Trim() }

      $sanResult = Invoke-External -File $openssl -Arguments @('x509', '-in', $certFile, '-noout', '-ext', 'subjectAltName') -TimeoutSec 10
      $sanText = $sanResult.Output
      if ($sanResult.ExitCode -ne 0 -or -not $sanText) {
        $sanResult = Invoke-External -File $openssl -Arguments @('x509', '-in', $certFile, '-noout', '-text') -TimeoutSec 10
        $sanText = $sanResult.Output
      }
      $dnsCount = ([regex]::Matches($sanText, 'DNS:')).Count
      if ($dnsCount -gt 0) { $sanCount = [string]$dnsCount }

      if ($handshake.Output -match 'Protocol\s*:\s*(\S+)') { $protocol = $matches[1] }
      elseif ($handshake.Output -match 'New,\s*(TLSv[0-9.]+)') { $protocol = $matches[1] }
    }
    Remove-Item -Path (Join-Path $script:TmpDir 'tls-cert.pem') -Force -ErrorAction SilentlyContinue
  }

  if (-not $subject) {
    $curl = Get-CurlExe
    if ($curl) {
      $verbose = Invoke-External -File $curl `
        -Arguments @('-sS', '-o', (Get-NullDevice), '-v', '--max-time', '15', '--url', ("https://{0}:{1}" -f $hostName, $port)) -TimeoutSec 20
      $text = "$($verbose.Error) `n $($verbose.Output)"
      $foundAny = $false
      if ($text -match '(?m)^\*\s+subject:\s*(.+)$') {
        $subjectText = $matches[1].Trim()
        if ($subjectText -match 'CN\s*=\s*([^,]+)') { $subject = $matches[1].Trim() } else { $subject = $subjectText }
        $foundAny = $true
      }
      if ($text -match '(?m)^\*\s+issuer:\s*(.+)$') { $issuer = $matches[1].Trim() }
      if ($text -match '(?m)^\*\s+start date:\s*(.+)$') { $notBefore = $matches[1].Trim() }
      if ($text -match '(?m)^\*\s+expire date:\s*(.+)$') { $notAfter = $matches[1].Trim() }
      if ($text -match 'SSL connection using\s+(\S+)') { $protocol = $matches[1] }
      if ($foundAny) { $method = 'curl -v' }
    }
  }

  if (-not $subject) {
    Write-Bad 'no certificate retrieved: openssl s_client and curl both failed (host unreachable, or neither tool present).'
    return
  }

  $daysLeft = $null
  if ($notAfter -ne '-') {
    $end = ConvertFrom-CertDate $notAfter
    if ($end) {
      $daysLeft = [int][math]::Floor(($end.ToUniversalTime() - [DateTime]::UtcNow).TotalDays)
    }
  }

  Write-Kv 'subject CN' $subject
  Write-Kv 'issuer' $issuer
  Write-Kv 'notBefore' $notBefore
  Write-Kv 'notAfter' $notAfter
  if ($null -ne $daysLeft) {
    $daysText = "$daysLeft"
    Write-Kv 'days left' $daysText
  } else {
    Write-Kv 'days left' 'unknown'
  }
  Write-Kv 'SAN count' $sanCount
  Write-Kv 'protocol' $protocol
  if (-not $Q) { Write-Note ("read with {0}" -f $method) }
  if ($null -ne $daysLeft -and $daysLeft -lt 21) {
    Write-Warn2 ("certificate expires in {0} days" -f $daysLeft)
  }
}

function Invoke-Trace {
  if (-not $Argument) {
    Write-Bad 'usage: .\dns-bench.ps1 trace HOST'
    return
  }
  $target = $Argument.Trim()
  Write-Section "Trace: $target"
  $traceroute = Get-BinPath @('traceroute')
  $tracepath = Get-BinPath @('tracepath')
  $tracert = Get-BinPath @('tracert')
  $result = $null
  $used = $null
  if ($traceroute) {
    $used = 'traceroute'
    $result = Invoke-External -File $traceroute -Arguments @('-n', '-q', '1', '-w', '1', '-m', '16', $target) -TimeoutSec 40
  } elseif ($tracepath) {
    $used = 'tracepath'
    $result = Invoke-External -File $tracepath -Arguments @('-n', '-m', '16', $target) -TimeoutSec 40
  } elseif ($tracert) {
    $used = 'tracert'
    $result = Invoke-External -File $tracert -Arguments @('-d', '-h', '16', '-w', '1000', $target) -TimeoutSec 60
  } else {
    Write-Bad 'trace needs traceroute, tracepath or tracert; none found.'
    return
  }
  if ($result.TimedOut) { Write-Warn2 'trace stopped at the timeout'; }
  $rows = @(ConvertFrom-TraceText -Text $result.Output)
  if ($rows.Count -eq 0) {
    Write-Warn2 ("no hops parsed from {0}" -f $used)
    if ($result.Error) { Write-Note $result.Error.Trim() }
    return
  }
  Write-Host ('  {0,-5} {1,-40} {2,9}' -f 'Hop', 'Address', 'RTT') -ForegroundColor White
  foreach ($row in $rows) {
    Write-Host ('  {0,-5} {1,-40} {2,9}' -f $row.Hop, $row.Address, $row.Rtt)
  }
  if (-not $Q) { Write-Note ("path: {0}, 16 hops max, one probe per hop" -f $used) }
}

function Invoke-Asn {
  if (-not $Argument) {
    Write-Bad 'usage: .\dns-bench.ps1 asn HOST|IP'
    return
  }
  $target = $Argument.Trim()
  $address = Resolve-FirstAddress $target
  if (-not $address) {
    Write-Bad ("could not resolve {0}" -f $target)
    return
  }
  Write-Section "ASN: $target ($target)"

  $reverse = Get-ReverseName $address
  if (-not $reverse) { Write-Bad ("not a usable IPv4/IPv6 address: {0}" -f $address); return }
  $suffix = 'origin.asn.cymru.com'
  if ($address -match ':') { $suffix = 'origin6.asn.cymru.com' }
  $queryName = ($reverse -replace '\.(in-addr|ip6)\.arpa$', ('.' + $suffix))

  $origin = (Get-TxtRecords -Name $queryName | Select-Object -First 1)
  if (-not $origin) {
    Write-Bad 'no ASN data (private/reserved address, or Team Cymru unreachable).'
    return
  }
  $fields = @($origin -split '\|' | ForEach-Object { $_.Trim() })
  while ($fields.Count -lt 5) { $fields += '' }
  $asnNumbers = @($fields[0] -split '\s+' | Where-Object { $_ })
  $asnText = @()
  foreach ($number in $asnNumbers) { $asnText += ('AS' + $number) }
  Write-Kv 'ASN' ($asnText -join ', ')
  Write-Kv 'BGP prefix' $fields[1]
  Write-Kv 'Country' $fields[2]
  Write-Kv 'Registry' $fields[3]
  if ($fields.Count -gt 4 -and $fields[4]) { Write-Kv 'Allocated' $fields[4] }

  $org = '-'
  if ($asnNumbers.Count -gt 0) {
    $detail = (Get-TxtRecords -Name ('AS{0}.asn.cymru.com' -f $asnNumbers[0]) | Select-Object -First 1)
    if ($detail) {
      $detailFields = @($detail -split '\|' | ForEach-Object { $_.Trim() })
      if ($detailFields.Count -ge 5 -and $detailFields[4]) { $org = $detailFields[4] }
    }
  }
  Write-Kv 'Org' $org
}

function Invoke-Ptr {
  if (-not $Argument) {
    Write-Bad 'usage: .\dns-bench.ps1 ptr IP'
    return
  }
  $address = $Argument.Trim()
  $reverse = Get-ReverseName $address
  if (-not $reverse) {
    Write-Bad ("not a valid IPv4/IPv6 address: {0}" -f $address)
    return
  }
  Write-Section "PTR: $address"

  $names = @()
  if (Get-Command Resolve-DnsName -ErrorAction SilentlyContinue) {
    try {
      $records = Resolve-DnsName -Name $reverse -Type PTR -DnsOnly -QuickTimeout -ErrorAction Stop
      foreach ($record in $records) { if ($record.NameHost) { $names += $record.NameHost.TrimEnd('.') } }
    } catch { }
  }
  if ($names.Count -eq 0) {
    $dig = Get-BinPath @('dig')
    if ($dig) {
      $result = Invoke-External -File $dig -Arguments @('+short', '+time=2', '+tries=1', 'PTR', $reverse) -TimeoutSec 6
      foreach ($line in ($result.Output -split "`n")) {
        $value = $line.Trim().TrimEnd('.')
        if ($value) { $names += $value }
      }
    }
  }
  if ($names.Count -eq 0) {
    Write-Note 'no PTR record'
    Write-Kv 'Forward-confirmed reverse DNS' 'no'
    return
  }
  foreach ($name in ($names | Select-Object -Unique)) {
    Write-Kv 'PTR' $name
  }
  $confirmed = $false
  foreach ($name in $names) {
    foreach ($forward in @(Resolve-AllAddresses $name)) {
      if ($forward -and (Test-SameAddress $forward $address)) { $confirmed = $true }
    }
  }
  if ($confirmed) { Write-Kv 'Forward-confirmed reverse DNS' 'yes' }
  else { Write-Kv 'Forward-confirmed reverse DNS' 'no' }
}

function Get-ResolverEgress {
  param([string]$Server)
  foreach ($name in @('o-o.myaddr.l.google.com')) {
    foreach ($value in (Get-TxtRecords -Name $name -Server $Server)) {
      $clean = $value.Trim().Trim('"')
      if ($clean -match '^(\d{1,3}\.){3}\d{1,3}$') { return $clean }
      if ($clean -match '^[0-9a-fA-F:]+$' -and $clean.Contains(':')) { return $clean }
    }
  }
  return $null
}

function Invoke-Leak {
  Write-Section 'DNS leak check'
  $public = $null
  if ($Privacy) {
    Write-Note 'Privacy mode: public IP lookup skipped.'
    Write-Kv 'Public IP' 'skipped (-Privacy)'
  } else {
    $public = Get-PublicIp
    if ($public) { Write-Kv 'Public IP' $public } else { Write-Kv 'Public IP' 'unknown' }
  }

  $systemEgress = Get-ResolverEgress -Server $null
  if ($systemEgress) { Write-Kv 'System resolver egress' $systemEgress }
  else { Write-Kv 'System resolver egress' 'no answer' }

  $configured = @(Get-ConfiguredDns)
  $egresses = @()
  if ($systemEgress) { $egresses += $systemEgress }
  if ($configured.Count -eq 0) { Write-Note 'no configured resolver addresses found' }
  foreach ($server in $configured) {
    $egress = Get-ResolverEgress -Server $server
    if ($egress) {
      Write-Kv ("Egress via {0}" -f $server) $egress
      $egresses += $egress
    } else {
      Write-Kv ("Egress via {0}" -f $server) 'no answer'
    }
  }

  $distinct = @($egresses | Select-Object -Unique)
  $mismatch = $false
  if ($public -and $systemEgress -and $systemEgress -ne $public) { $mismatch = $true }
  if ($public) {
    foreach ($egress in $distinct) { if ($egress -ne $public) { $mismatch = $true } }
  }
  if ($distinct.Count -gt 1) { $mismatch = $true }

  $verdict = 'no mismatch found'
  if ($mismatch) {
    if ($public) {
      $verdict = 'mismatch: DNS leaves through a different network than your public IP'
    } else {
      $verdict = 'mismatch: resolvers leave through different networks'
    }
  }
  Write-Kv 'Verdict' $verdict
  if ($mismatch) {
    Write-Note 'A mismatch is normal behind a router or ISP resolver and expected with a VPN split tunnel; it can also mean a DNS leak.'
  }
}

function Invoke-Propagation {
  if (-not $Argument) {
    Write-Bad 'usage: .\dns-bench.ps1 propagation DOMAIN [TYPE]'
    return
  }
  $target = $Argument.Trim()
  $type = 'A'
  if ($Rest -and $Rest.Count -gt 0) { $type = $Rest[0].ToUpper() }
  $allowed = @('A', 'AAAA', 'CNAME', 'NS', 'MX', 'TXT', 'SOA', 'CAA')
  if ($allowed -notcontains $type) {
    Write-Bad ("unsupported record type: {0} (use {1})" -f $type, ($allowed -join ', '))
    return
  }
  $resolvers = @(
    @('Cloudflare', '1.1.1.1'),
    @('Google', '8.8.8.8'),
    @('Quad9', '9.9.9.9'),
    @('OpenDNS', '208.67.222.222'),
    @('AdGuard', '94.140.14.14'),
    @('Control D', '76.76.2.0'),
    @('Verisign', '64.6.64.6'),
    @('DNS.WATCH', '84.200.69.80')
  )
  Write-Section ("Propagation: {0} ({1})" -f $target, $type)
  Write-Host ('  {0,-14} {1,-10} {2}' -f 'Resolver', 'Status', 'Answer') -ForegroundColor White
  $groups = @{}
  foreach ($entry in $resolvers) {
    $record = Get-RecordValues -Server $entry[1] -Name $target -Type $type
    $answerText = '-'
    if ($record.Values.Count -gt 0) {
      $answerText = ($record.Values -join ', ')
      if ($answerText.Length -gt 68) { $answerText = $answerText.Substring(0, 65) + '...' }
    }
    Write-Host ('  {0,-14} {1,-10} {2}' -f $entry[0], $record.Status, $answerText)
    $key = ($record.Values | Sort-Object) -join ';'
    if (-not $key) { $key = "<no answer>" }
    if (-not $groups.ContainsKey($key)) { $groups[$key] = @() }
    $groups[$key] += $entry[0]
  }

  $topKey = $null
  $topCount = 0
  foreach ($key in $groups.Keys) {
    if ($groups[$key].Count -gt $topCount) { $topCount = $groups[$key].Count; $topKey = $key }
  }
  Write-Host ''
  Write-Kv 'Agreement' ("{0}/{1} resolvers return the most common answer" -f $topCount, $resolvers.Count)
  Write-Kv 'Distinct answers' ([string]$groups.Keys.Count)
  foreach ($key in ($groups.Keys | Sort-Object { $groups[$_].Count } -Descending)) {
    $names = $groups[$key] -join ', '
    $shown = $key
    if ($shown.Length -gt 60) { $shown = $shown.Substring(0, 57) + '...' }
    Write-Host ('  {0,2}/{1}  {2}  [{3}]' -f $groups[$key].Count, $resolvers.Count, $shown, $names)
  }
  if ($groups.Keys.Count -gt 1) {
    Write-Note 'Different answers can be normal for CDNs and geo-DNS; for a single-host record they mean propagation is incomplete.'
  }
}

function Invoke-Mtu {
  if (-not $Argument) {
    Write-Bad 'usage: .\dns-bench.ps1 mtu HOST'
    return
  }
  $target = $Argument.Trim()
  Write-Section "Path MTU: $target"
  $ping = Get-BinPath @('ping')
  if (-not $ping) {
    Write-Bad 'mtu needs ping; not found.'
    return
  }
  if (-not (Test-DfPing -PingExe $ping -Target $target -Payload 56)) {
    Write-Bad ("no reply from {0} (ICMP blocked or host down)" -f $target)
    return
  }
  $low = 56
  $high = 1472
  $best = 56
  while ($low -le $high) {
    $mid = [int][math]::Floor(($low + $high) / 2)
    if (Test-DfPing -PingExe $ping -Target $target -Payload $mid) {
      $best = $mid
      $low = $mid + 1
    } else {
      $high = $mid - 1
    }
  }
  Write-Kv 'Path MTU' ("{0} bytes" -f ($best + 28))
  Write-Kv 'Payload size' ("{0} bytes" -f $best)
  if ($best -lt 1472) {
    Write-Note 'Below Ethernet 1500: a tunnel, VPN or PPPoE is shrinking the path MTU.'
  } else {
    Write-Note 'Standard Ethernet MTU.'
  }
}

function Invoke-Ecs {
  $target = $Domain
  if ($Argument) { $target = $Argument.Trim() }
  Write-Section ("EDNS Client Subnet: {0}" -f $target)
  $dig = Get-BinPath @('dig')
  if (-not $dig) {
    Write-Bad 'ecs needs dig (the only tool here that can send EDNS Client Subnet); not found.'
    return
  }
  if ($Privacy) {
    Write-Bad 'ecs needs your public IP to build the subnet; -Privacy blocks that lookup.'
    return
  }
  $public = Get-PublicIp
  if (-not $public) {
    Write-Bad 'could not determine your public IP; cannot build an ECS subnet.'
    return
  }
  if ($public -match ':') {
    Write-Bad ("public address is IPv6 ({0}); this check builds an IPv4 /24 subnet" -f $public)
    return
  }
  $subnet = ($public -split '\.')[0..2] -join '.'
  $plain = Invoke-External -File $dig -Arguments @('+short', '+time=2', '+tries=1', '@8.8.8.8', $target, 'A', '+subnet=0') -TimeoutSec 8
  $ecs = Invoke-External -File $dig -Arguments @('+short', '+time=2', '+tries=1', '@8.8.8.8', $target, 'A', ('+subnet={0}/24' -f $subnet)) -TimeoutSec 8

  $plainValues = @(($plain.Output -split "`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Sort-Object)
  $ecsValues = @(($ecs.Output -split "`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Sort-Object)
  Write-Kv 'resolver' '8.8.8.8'
  Write-Kv 'without ECS (+subnet=0)' $(if ($plainValues.Count) { $plainValues -join ', ' } else { '-' })
  Write-Kv ('with ECS (+subnet={0}/24)' -f $subnet) $(if ($ecsValues.Count) { $ecsValues -join ', ' } else { '-' })
  $changed = (($plainValues -join ',') -ne ($ecsValues -join ','))
  Write-Kv 'ECS changes the answer' $(if ($changed) { 'yes' } else { 'no' })
  Write-Note 'A "yes" means this resolver geo-steers on your subnet; cached results from other subnets cannot be compared with yours.'
}

function Invoke-Ifaces {
  Write-Section 'Network interfaces'
  if (Get-Command Get-NetAdapter -ErrorAction SilentlyContinue) {
    Write-Host ('  {0,-18} {1,-8} {2,-6} {3,-18} {4,-18} {5,-26} {6}' -f 'Interface', 'State', 'MTU', 'MAC', 'IPv4', 'IPv6', 'Media') -ForegroundColor White
    $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Sort-Object InterfaceIndex)
    foreach ($adapter in $adapters) {
      $mtu = $adapter.MtuSize
      if (-not $mtu) {
        $ipInterface = Get-NetIPInterface -InterfaceIndex $adapter.ifIndex -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($ipInterface) { $mtu = $ipInterface.NlMtu }
      }
      $addresses = @(Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -ErrorAction SilentlyContinue)
      $v4 = @($addresses | Where-Object { $_.AddressFamily -eq 'IPv4' -and $_.IPAddress -notmatch '^169\.254\.' } | ForEach-Object { $_.IPAddress })
      $v6 = @($addresses | Where-Object { $_.AddressFamily -eq 'IPv6' -and $_.IPAddress -notmatch '^fe80' } | ForEach-Object { $_.IPAddress })
      $media = $adapter.MediaType
      if ($adapter.PhysicalMediaType) { $media = $adapter.PhysicalMediaType }
      Write-Host ('  {0,-18} {1,-8} {2,-6} {3,-18} {4,-18} {5,-26} {6}' -f $adapter.Name, $adapter.Status,
        $(if ($mtu) { $mtu } else { '-' }), $adapter.MacAddress,
        $(if ($v4.Count) { $v4 -join ',' } else { '-' }),
        $(if ($v6.Count) { $v6 -join ',' } else { '-' }), $media)
    }
    return
  }

  $ifconfig = Get-BinPath @('ifconfig')
  if (-not $ifconfig) {
    Write-Bad 'ifaces needs Get-NetAdapter or ifconfig; none found.'
    return
  }
  $result = Invoke-External -File $ifconfig -Arguments @('-a') -TimeoutSec 8
  if (-not $result.Output) {
    Write-Bad 'ifconfig returned no data.'
    return
  }
  $rows = @()
  $current = $null
  foreach ($line in ($result.Output -split "`n")) {
    if ($line -match '^([A-Za-z0-9_.:-]+):\s+.*mtu\s+(\d+)') {
      if ($current) { $rows += $current }
      $name = $matches[1]
      $mtu = [int]$matches[2]
      $flags = ''
      if ($line -match 'flags=\d+<([^>]*)>') { $flags = $matches[1] }
      $state = 'down'
      if ($flags -match 'UP' -and $flags -match 'RUNNING') { $state = 'up' }
      $media = ''
      if ($flags -match 'LOOPBACK') { $media = 'loopback' }
      $current = [pscustomobject]@{
        Name = $name; State = $state; Mtu = $mtu; Mac = '-'
        V4 = @(); V6 = @(); Media = $media
      }
    } elseif ($current) {
      if ($line -match '^\s+ether\s+(\S+)') { $current.Mac = $matches[1] }
      elseif ($line -match '^\s+inet\s+(\d{1,3}(?:\.\d{1,3}){3})') { $current.V4 += $matches[1] }
      elseif ($line -match '^\s+inet6\s+([0-9a-fA-F:]+)') {
        if ($matches[1] -notmatch '^fe80') { $current.V6 += $matches[1] }
      }
      elseif ($line -match '^\s+media:\s*(.+)$') { $current.Media = $matches[1].Trim() }
      elseif ($line -match '^\s+status:\s*(\S+)') { $current.State = $matches[1] }
    }
  }
  if ($current) { $rows += $current }

  Write-Host ('  {0,-18} {1,-8} {2,-6} {3,-18} {4,-18} {5,-26} {6}' -f 'Interface', 'State', 'MTU', 'MAC', 'IPv4', 'IPv6', 'Media') -ForegroundColor White
  foreach ($row in $rows) {
    Write-Host ('  {0,-18} {1,-8} {2,-6} {3,-18} {4,-18} {5,-26} {6}' -f $row.Name, $row.State, $row.Mtu, $row.Mac,
      $(if ($row.V4.Count) { ($row.V4 | Select-Object -Unique) -join ',' } else { '-' }),
      $(if ($row.V6.Count) { ($row.V6 | Select-Object -Unique) -join ',' } else { '-' }),
      $(if ($row.Media) { $row.Media } else { '-' }))
  }
}

function Invoke-Listen {
  Write-Section 'Listening TCP sockets'
  Write-Host ('  {0,-6} {1,-30} {2}' -f 'Proto', 'Local address:port', 'Process') -ForegroundColor White

  if (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue) {
    $connections = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Sort-Object LocalPort)
    foreach ($connection in $connections) {
      $processName = '-'
      if ($connection.OwningProcess) {
        $process = Get-Process -Id $connection.OwningProcess -ErrorAction SilentlyContinue
        if ($process) { $processName = $process.ProcessName }
      }
      Write-Host ('  {0,-6} {1,-30} {2}' -f 'TCP', ("{0}:{1}" -f $connection.LocalAddress, $connection.LocalPort), $processName)
    }
    return
  }

  $lsof = Get-BinPath @('lsof')
  if ($lsof) {
    $result = Invoke-External -File $lsof -Arguments @('-nP', '-iTCP', '-sTCP:LISTEN', '-F', 'cn') -TimeoutSec 10
    $commandName = '-'
    foreach ($line in ($result.Output -split "`n")) {
      if ($line -match '^c(.+)$') {
        $commandName = $matches[1]
      } elseif ($line -match '^n(.+)$') {
        Write-Host ('  {0,-6} {1,-30} {2}' -f 'TCP', $matches[1], $commandName)
      }
    }
    return
  }

  $netstat = Get-BinPath @('netstat')
  if ($netstat) {
    $result = Invoke-External -File $netstat -Arguments @('-an') -TimeoutSec 10
    foreach ($line in ($result.Output -split "`n")) {
      if ($line -notmatch 'LISTEN') { continue }
      $fields = @($line -split '\s+' | Where-Object { $_ })
      if ($fields.Count -ge 4) {
        Write-Host ('  {0,-6} {1,-30} {2}' -f $fields[0], $fields[3], '-')
      }
    }
    return
  }

  Write-Bad 'listen needs Get-NetTCPConnection, lsof or netstat; none found.'
}

function Get-WifiBand([string]$Channel) {
  if (-not $Channel) { return '-' }
  $value = 0
  if ($Channel -match '(\d+)') { $value = [int]$matches[1] }
  if ($value -eq 0) { return '-' }
  if ($value -le 14) { return '2.4 GHz' }
  if ($value -ge 32 -and $value -le 177) { return '5 GHz' }
  if ($value -gt 177) { return '6 GHz' }
  return '-'
}

function Invoke-Wifi {
  Write-Section 'Wi-Fi link'

  if ($script:OnWindows) {
    $netsh = Get-BinPath @('netsh')
    if (-not $netsh) { Write-Bad 'wifi needs netsh; not found.'; return }
    $result = Invoke-External -File $netsh -Arguments @('wlan', 'show', 'interfaces') -TimeoutSec 8
    if (-not $result.Output -or $result.Output -notmatch 'SSID') {
      Write-Bad 'no wireless interface reported (netsh wlan show interfaces).'
      return
    }
    $info = @{}
    foreach ($line in ($result.Output -split "`n")) {
      if ($line -match '^\s*([^:]+?)\s*:\s*(.+?)\s*$') {
        $key = $matches[1].Trim()
        if (-not $info.ContainsKey($key)) { $info[$key] = $matches[2].Trim() }
      }
    }
    $signal = '-'
    $rssi = '-'
    if ($info.ContainsKey('Signal')) {
      $signal = $info['Signal']
      if ($signal -match '^(\d+)%$') {
        $rssi = ('{0}% (~{1} dBm)' -f $signal, ([int]([int]$matches[1] / 2) - 100))
      }
    }
    $channel = '-'
    if ($info.ContainsKey('Channel')) { $channel = $info['Channel'] }
    $band = '-'
    if ($info.ContainsKey('Band')) { $band = $info['Band'] }
    elseif ($channel -ne '-') { $band = Get-WifiBand $channel }
    $security = '-'
    if ($info.ContainsKey('Authentication')) { $security = $info['Authentication'] }
    if ($info.ContainsKey('Cipher')) { $security = "$security / $($info['Cipher'])" }
    Write-Kv 'SSID' $(if ($info.ContainsKey('SSID')) { $info['SSID'] } else { '-' })
    Write-Kv 'BSSID' $(if ($info.ContainsKey('BSSID')) { $info['BSSID'] } else { '-' })
    Write-Kv 'Channel' $channel
    Write-Kv 'Band' $band
    Write-Kv 'RSSI / signal' $rssi
    Write-Kv 'Noise' 'n/a (not exposed by netsh)'
    Write-Kv 'Tx rate' $(if ($info.ContainsKey('Transmit rate (Mbps)')) { "$($info['Transmit rate (Mbps)']) Mbps" } else { '-' })
    Write-Kv 'Security' $security
    return
  }

  if ($script:OSKind -eq 'macos') {
    $airport = '/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport'
    if (Test-Path $airport) {
      $result = Invoke-External -File $airport -Arguments @('-I') -TimeoutSec 8
      if ($result.Output -match 'agrCtlRSSI') {
        $map = @{}
        foreach ($line in ($result.Output -split "`n")) {
          if ($line -match '^\s*([^:]+):\s*(.+)$') { $map[$matches[1].Trim()] = $matches[2].Trim() }
        }
        $channel = '-'
        if ($map.ContainsKey('channel')) { $channel = (($map['channel'] -split ',')[0]).Trim() }
        Write-Kv 'SSID' $(if ($map.ContainsKey('SSID')) { $map['SSID'] } else { '-' })
        Write-Kv 'BSSID' $(if ($map.ContainsKey('BSSID')) { $map['BSSID'] } else { '-' })
        Write-Kv 'Channel' $channel
        Write-Kv 'Band' (Get-WifiBand $channel)
        Write-Kv 'RSSI / signal' $(if ($map.ContainsKey('agrCtlRSSI')) { "$($map['agrCtlRSSI']) dBm" } else { '-' })
        Write-Kv 'Noise' $(if ($map.ContainsKey('agrCtlNoise')) { "$($map['agrCtlNoise']) dBm" } else { '-' })
        Write-Kv 'Tx rate' $(if ($map.ContainsKey('lastTxRate')) { "$($map['lastTxRate']) Mbps" } else { '-' })
        Write-Kv 'Security' $(if ($map.ContainsKey('link auth')) { $map['link auth'] } else { '-' })
        return
      }
    }
    $wdutil = Get-BinPath @('wdutil')
    if ($wdutil) {
      $result = Invoke-External -File $wdutil -Arguments @('info') -TimeoutSec 8
      if ($result.Output -match 'SSID') {
        $map = @{}
        foreach ($line in ($result.Output -split "`n")) {
          if ($line -match '^\s*([^:]+):\s*(.+)$') { $map[$matches[1].Trim()] = $matches[2].Trim() }
        }
        $channel = '-'
        if ($map.ContainsKey('Channel')) { $channel = $map['Channel'] }
        Write-Kv 'SSID' $(if ($map.ContainsKey('SSID')) { $map['SSID'] } else { '-' })
        Write-Kv 'BSSID' $(if ($map.ContainsKey('BSSID')) { $map['BSSID'] } else { '-' })
        Write-Kv 'Channel' $channel
        Write-Kv 'Band' (Get-WifiBand $channel)
        Write-Kv 'RSSI / signal' $(if ($map.ContainsKey('RSSI')) { "$($map['RSSI']) dBm" } else { '-' })
        Write-Kv 'Noise' $(if ($map.ContainsKey('Noise')) { "$($map['Noise']) dBm" } else { '-' })
        Write-Kv 'Tx rate' $(if ($map.ContainsKey('Tx Rate')) { $map['Tx Rate'] } else { '-' })
        Write-Kv 'Security' $(if ($map.ContainsKey('Security')) { $map['Security'] } else { '-' })
        return
      }
    }
    Write-Bad 'no Wi-Fi info: airport is gone on current macOS and wdutil returned nothing (wdutil info needs sudo).'
    return
  }

  $iw = Get-BinPath @('iw')
  if ($iw) {
    $devices = Invoke-External -File $iw -Arguments @('dev') -TimeoutSec 6
    $interface = $null
    if ($devices.Output -match 'Interface\s+(\S+)') { $interface = $matches[1] }
    if ($interface) {
      $link = Invoke-External -File $iw -Arguments @('dev', $interface, 'link') -TimeoutSec 6
      if ($link.Output -match 'SSID:\s*(.+)') {
        Write-Kv 'SSID' $matches[1].Trim()
      }
      if ($link.Output -match 'Connected to\s+([0-9a-fA-F:]+)') { Write-Kv 'BSSID' $matches[1] }
      elseif ($link.Output -match '^\s*BSSID:\s*([0-9a-fA-F:]+)') { Write-Kv 'BSSID' $matches[1] }
      $frequency = 0
      if ($link.Output -match 'freq:\s*(\d+)') { $frequency = [int]$matches[1] }
      $channel = '-'
      if ($frequency -gt 0) { $channel = [string][int](($frequency - 2407) / 5) }
      Write-Kv 'Channel' $channel
      Write-Kv 'Band' (Get-WifiBand $channel)
      Write-Kv 'RSSI / signal' $(if ($link.Output -match 'signal:\s*(-?\d+)\s*dBm') { "$($matches[1]) dBm" } else { '-' })
      Write-Kv 'Noise' 'n/a'
      Write-Kv 'Tx rate' $(if ($link.Output -match 'tx bitrate:\s*([\d.]+)\s*MBit/s') { "$($matches[1]) Mbps" } else { '-' })
      Write-Kv 'Security' '-'
      return
    }
  }
  $nmcli = Get-BinPath @('nmcli')
  if ($nmcli) {
    $result = Invoke-External -File $nmcli -Arguments @('-t', '-f', 'ACTIVE,SSID,BSSID,CHAN,SIGNAL,RATE,SECURITY', 'dev', 'wifi') -TimeoutSec 10
    foreach ($line in ($result.Output -split "`n")) {
      if ($line -match '^yes:') {
        $fields = $line -split ':'
        if ($fields.Count -ge 7) {
          Write-Kv 'SSID' $fields[1]
          Write-Kv 'BSSID' $fields[2]
          Write-Kv 'Channel' $fields[3]
          Write-Kv 'Band' (Get-WifiBand $fields[3])
          Write-Kv 'RSSI / signal' ("{0}%" -f $fields[4])
          Write-Kv 'Noise' 'n/a'
          Write-Kv 'Tx rate' $fields[5]
          Write-Kv 'Security' $fields[6]
        }
        return
      }
    }
  }
  Write-Bad 'wifi needs netsh, airport/wdutil, iw or nmcli; none reported a wireless link.'
}

function Invoke-Doctor {
  Write-Section 'Doctor'
  $checks = @()
  $missingRequired = 0

  $dnsEngine = Get-Command Resolve-DnsName -ErrorAction SilentlyContinue
  if ($dnsEngine) {
    $checks += [pscustomobject]@{ Check = 'Resolve-DnsName (DNS engine)'; Required = $true; Present = $true; Detail = $dnsEngine.Source }
  } else {
    $checks += [pscustomobject]@{ Check = 'Resolve-DnsName (DNS engine)'; Required = $true; Present = $false; Detail = 'missing: this build targets Windows; use dns-bench.zsh here' }
    $missingRequired++
  }

  $dig = Get-BinPath @('dig')
  $digRequired = -not $script:OnWindows
  if (-not $dig) {
    if ($digRequired) { $missingRequired++ }
  }
  $checks += [pscustomobject]@{ Check = 'dig'; Required = $digRequired; Present = [bool]$dig; Detail = $(if ($dig) { $dig } else { 'missing: ecs and the non-Windows DNS fallback need it' }) }

  $curl = Get-CurlExe
  if (-not $curl) { $missingRequired++ }
  $checks += [pscustomobject]@{ Check = 'curl'; Required = $true; Present = [bool]$curl; Detail = $(if ($curl) { $curl } else { 'missing: http, tls fallback, public IP, speed need it' }) }

  $ping = Get-BinPath @('ping')
  if (-not $ping) { $missingRequired++ }
  $checks += [pscustomobject]@{ Check = 'ping'; Required = $true; Present = [bool]$ping; Detail = $(if ($ping) { $ping } else { 'missing: mtu and speed latency need it' }) }

  $openssl = Get-BinPath @('openssl')
  $checks += [pscustomobject]@{ Check = 'openssl'; Required = $false; Present = [bool]$openssl; Detail = $(if ($openssl) { $openssl } else { 'optional: tls falls back to curl -v' }) }

  $perl = Get-BinPath @('perl')
  $checks += [pscustomobject]@{ Check = 'perl'; Required = $false; Present = [bool]$perl; Detail = $(if ($perl) { $perl } else { 'optional: not used on Windows' }) }

  $traceroute = Get-BinPath @('traceroute', 'tracepath', 'tracert')
  $checks += [pscustomobject]@{ Check = 'traceroute / tracepath / tracert'; Required = $false; Present = [bool]$traceroute; Detail = $(if ($traceroute) { $traceroute } else { 'optional: trace needs one of them' }) }

  $lsof = Get-BinPath @('lsof')
  $netstat = Get-BinPath @('netstat')
  $checks += [pscustomobject]@{ Check = 'lsof / netstat'; Required = $false; Present = [bool]($lsof -or $netstat); Detail = $(if ($lsof) { $lsof } elseif ($netstat) { $netstat } else { 'optional on Windows: Get-NetTCPConnection is used' }) }

  $platformTool = Get-BinPath @('netsh', 'networksetup', 'nmcli', 'scutil')
  $checks += [pscustomobject]@{ Check = 'netsh / networksetup / nmcli'; Required = $false; Present = [bool]$platformTool; Detail = $(if ($platformTool) { $platformTool } else { 'optional: only used by info/wifi/reset' }) }

  Write-Host ('  {0,-34} {1,-9} {2,-8} {3}' -f 'Check', 'Required', 'Status', 'Detail') -ForegroundColor White
  foreach ($check in $checks) {
    $status = 'missing'
    $color = 'Red'
    if ($check.Present) { $status = 'ok'; $color = 'Green' }
    elseif (-not $check.Required) { $status = 'optional'; $color = 'Yellow' }
    $requiredText = 'no'
    if ($check.Required) { $requiredText = 'yes' }
    Write-Host ('  {0,-34} {1,-9} {2,-8} {3}' -f $check.Check, $requiredText, $status, $check.Detail) -ForegroundColor $color
  }

  Write-Host ''
  Write-Section 'Install and state'
  $privilege = 'no'
  if ($script:OnWindows) {
    if ($script:IsAdmin) { $privilege = 'yes (elevated)' } else { $privilege = 'no (changing DNS needs Run as Administrator)' }
  } else {
    $privilege = 'not applicable (Windows-only DNS control)'
  }
  Write-Kv 'Privileges' $privilege
  Write-Kv 'Script' $script:SelfPath
  Write-Kv 'Version' ("{0} (PowerShell {1})" -f $script:Version, $PSVersionTable.PSVersion.ToString())

  $installed = Get-Command 'dns-bench.ps1' -ErrorAction SilentlyContinue
  if ($installed) { Write-Kv 'Installed copy' $installed.Source }
  else { Write-Kv 'Installed copy' 'not on PATH (run this file directly)' }

  $schedule = 'none'
  if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
    try {
      $task = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like '*dns-bench*' } | Select-Object -First 1
      if ($task) { $schedule = "$($task.TaskName) [$($task.State)]" }
    } catch { }
  }
  Write-Kv 'Schedule' $schedule

  $log = Join-Path $HOME '.dns-bench-previous.txt'
  if (Test-Path $log) {
    Write-Kv 'Change log' $log
    foreach ($line in (Get-Content -Path $log -Tail 3 -ErrorAction SilentlyContinue)) {
      Write-Note $line
    }
  } else {
    Write-Kv 'Change log' 'none yet'
  }

  Write-Host ''
  if ($missingRequired -gt 0) {
    Write-Bad ("  {0} required dependency/dependencies missing. Fix those before benchmarking." -f $missingRequired)
    exit 1
  }
  Write-Good '  All required dependencies are present.'
}

# =====================================================================
# dispatch
# =====================================================================
if ($Command -eq 'help') {
  if ($Argument) { exit (Show-CommandHelp -Name $Argument) }
  Show-Usage
  exit 0
}
if ($Command -eq 'version') { Write-Host "dns-bench $($script:Version) (PowerShell)"; exit 0 }

$windowsOnly = @('run', 'info', 'test', 'best', 'adblock', 'set', 'reset', 'status', 'list', 'flush')
if ($windowsOnly -contains $Command -and $Command -ne 'flush' -and -not (Get-Command Resolve-DnsName -ErrorAction SilentlyContinue)) {
  Write-Bad 'This command needs Windows: Resolve-DnsName is not available here.'
  Write-Host 'Use dns-bench.zsh on macOS or Linux. The speed test works everywhere PowerShell 7 runs:'
  Write-Host '  pwsh ./dns-bench.ps1 speed'
  exit 1
}

$script:HasV6 = $false
$script:Results = @()
$script:Domain = $Domain

try {
  switch ($Command) {
    'run' { Invoke-Run }
    'info' {
      Build-Resolvers
      $script:HasV6 = Test-IPv6Working
      Show-NetworkInfo
    }
    'test' { Invoke-Test }
    'best' { Invoke-Best }
    'adblock' { Invoke-Adblock }
    'set' { Invoke-Set }
    'reset' { Invoke-Reset }
    'status' { Invoke-Status }
    'list' { Invoke-List }
    'speed' { Invoke-Speed }
    'flush' { Invoke-Flush }
    'demo' { Invoke-Demo }
    'update' { Invoke-Update }
    'ports' { Invoke-Ports }
    'http' { Invoke-Http }
    'tls' { Invoke-Tls }
    'trace' { Invoke-Trace }
    'asn' { Invoke-Asn }
    'ptr' { Invoke-Ptr }
    'leak' { Invoke-Leak }
    'propagation' { Invoke-Propagation }
    'mtu' { Invoke-Mtu }
    'ecs' { Invoke-Ecs }
    'ifaces' { Invoke-Ifaces }
    'listen' { Invoke-Listen }
    'wifi' { Invoke-Wifi }
    'doctor' { Invoke-Doctor }
    default {
      Write-Bad "Unknown command: $Command"
      $suggestion = Get-ClosestCommand $Command
      if ($suggestion) { Write-Host "Did you mean: ${suggestion}? Try: .\dns-bench.ps1 help $suggestion" }
      else { Write-Host 'Run: .\dns-bench.ps1 help' }
      exit 1
    }
  }
} finally {
  Remove-Item -Path $script:TmpDir -Recurse -Force -ErrorAction SilentlyContinue
}

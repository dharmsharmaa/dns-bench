# credits

`dns-bench` is a small script standing on a lot of other people's infrastructure. This file lists what it depends on and who runs it. Nothing here implies endorsement, partnership, or sponsorship in either direction.

Maintained by [Dharm Sharma](https://dharmsharma.com). MIT licensed — see [LICENSE](./LICENSE).

## resolver operators

These are the public DNS endpoints the benchmark probes. Their resolvers are free to query and their operators publish the addresses; that is the whole reason this tool can exist.

| operator | resolver |
|---|---|
| [Cloudflare](https://www.cloudflare.com/learning/dns/what-is-1.1.1.1/) | 1.1.1.1 / 1.0.0.1, families and malware variants |
| [Google Public DNS](https://developers.google.com/speed/public-dns) | 8.8.8.8 / 8.8.4.4 |
| [Quad9](https://www.quad9.net/) | 9.9.9.9, unfiltered and filtered |
| [Cisco OpenDNS](https://www.opendns.com/) | 208.67.222.222 / 208.67.220.220, family shield |
| [AdGuard DNS](https://adguard-dns.io/) | default, family, unfiltered |
| [Control D](https://controld.com/) | free and unfiltered endpoints |
| [NextDNS](https://nextdns.io/) | anycast endpoints |
| [Mullvad](https://mullvad.net/en/help/dns-over-https-and-dns-over-tls) | public DNS |
| [CleanBrowsing](https://cleanbrowsing.org/) | security, family, adult filters |
| [DNS.SB](https://dns.sb/) | 185.222.222.222 / 45.11.45.11 |
| [Comodo Secure DNS](https://www.comodo.com/secure-dns/) | 8.26.56.26 / 8.20.247.20 |
| [Verisign Public DNS](https://publicdns.verisign.com/) | 64.6.64.6 / 64.6.65.6 |
| [Lumen / Level3](https://www.lumen.com/) | 4.2.2.1–4.2.2.6 |
| [Neustar UltraDNS](https://www.neustar.biz/services/ultradns) | public recursive endpoints |
| [Hurricane Electric](https://dns.he.net/) | ordns.he.net |
| [OpenNIC](https://www.opennic.org/) | community resolvers |
| [CIRA Shield](https://www.cira.ca/en/canadian-shield/) | Canadian Shield endpoints |
| [DNS4EU](https://www.joindns4.eu/) | EU public resolver |
| [DNS0.eu](https://www.dns0.eu/) | European public resolver |
| [DNS.WATCH](https://dns.watch/) | 84.200.69.80 / 84.200.70.40 |
| [UncensoredDNS](https://blog.uncensoreddns.org/) | 91.239.100.100 / 89.233.43.71 |
| [Digitale Gesellschaft](https://www.digitale-gesellschaft.ch/dns/) | Swiss public resolver |
| [SafeDNS](https://www.safedns.com/) | public/family endpoints |
| [Yandex DNS](https://dns.yandex.com/) | basic and safe |
| [TWNIC Quad101](https://101.101.101.101/) | 101.101.101.101 |
| [AliDNS](https://www.alidns.com/) | 223.5.5.5 / 223.6.6.6 |
| [DNSPod / Tencent](https://www.dnspod.com/) | 119.29.29.29 |
| [Baidu DNS](https://dudns.baidu.com/) | 180.76.76.76 |
| [CNNIC](https://www.cnnic.cn/) | 1.2.4.8 / 210.2.4.8 |
| [KT](https://www.kt.com/) | 168.126.63.1 / 168.126.63.2 |
| [LG U+](https://www.lguplus.com/) | 164.124.101.2 |
| [SingTel](https://www.singtel.com/) | 165.21.83.88 / 165.21.100.88 |

All trademarks and service marks belong to their respective owners. Being on this list is not an endorsement of `dns-bench`, and it is not a claim that a resolver is good, private, or safer than another. Resolver IPs and hostnames change without notice; if one is wrong or dead, please open an issue (see below).

## measurement and data endpoints

These services make the measurements possible. They are used at runtime, not bundled.

| endpoint | used for |
|---|---|
| [`speed.cloudflare.com`](https://speed.cloudflare.com/) | download and upload throughput |
| [`1.1.1.1/cdn-cgi/trace`](https://1.1.1.1/cdn-cgi/trace) | public IP and Cloudflare PoP identification |
| [`proof.ovh.net`](https://proof.ovh.net/) | fallback download mirror when Cloudflare rate-limits |
| [`ipwho.is`](https://ipwho.is/) | geolocation and ASN for the public IP |
| [`ipinfo.io`](https://ipinfo.io/) | secondary geo/ASN lookup |
| `sigok.verteiltesysteme.net` / `sigfail.verteiltesysteme.net` | public DNSSEC validation test domains |
| `ec2.<region>.amazonaws.com` | TCP connect latency to AWS regions on each continent |
| [`captive.apple.com`](https://captive.apple.com/) | captive-portal detection on macOS |
| [`msftconnecttest.com`](http://www.msftconnecttest.com/connecttest.txt) | captive-portal detection on Windows |
| `myip.opendns.com` | resolver egress IP check |
| `whoami.akamai.net` | resolver egress IP check (alternate) |

These are third-party services with their own terms, rate limits, and availability. `dns-bench` sends only the queries needed for the measurement, and `-P` / `-Privacy` skips the external IP and geo lookups. Nothing is sent to the author.

## tools relied on

The CLI is glue around utilities that already ship with your OS.

**macOS / Linux**

- [`dig`](https://www.isc.org/bind/) from BIND 9 (ISC) — the actual DNS queries
- [`curl`](https://curl.se/) — HTTP probes, speed test, DNSSEC test domains
- `ping` / `ping6` — latency, jitter, packet loss
- `traceroute` / `tracepath` — path inspection
- macOS `scutil`, `networksetup`, `ipconfig`, `ifconfig`, `route`, `osascript`, `launchd` — reading and changing network/DNS state
- Linux `ip`, `nmcli` / NetworkManager, `resolvectl` / systemd-resolved, `cron` / systemd timers

**Windows**

- `Resolve-DnsName`, `Get-NetAdapter`, `Set-DnsClientServerAddress`, `Clear-DnsClientCache`, `ipconfig`
- Windows Task Scheduler for scheduled runs

## runtime and frameworks

- [Node.js](https://nodejs.org/) — runtime and build tooling for the Mac app
- [Electron](https://www.electronjs.org/) (MIT) — app chassis and Chromium renderer
- macOS system fonts (SF Pro) and Apple's [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/) — the app's typography, spacing, and motion are modelled on them

No third-party npm packages are used at runtime. The app's `devDependencies` are `electron` and `@electron/packager` only; everything else is the platform.

## inspiration and prior art

The idea of measuring resolvers from where you actually sit is not new, and this project did not invent it. Credit to:

- [GRC DNS Benchmark](https://www.grc.com/dns/benchmark.htm) — the classic "test the resolvers yourself" tool
- [DNSPerf](https://www.dnsperf.com/) and [dnsperf.com](https://www.dnsperf.com/dns-speed-benchmark) — public resolver performance data
- the resolver documentation and public test pages from [Cloudflare](https://developers.cloudflare.com/1.1.1.1/) and [Google](https://developers.google.com/speed/public-dns/docs/performance)
- the many DNS benchmark scripts and blog posts that came before this one

No code was copied from these projects. The debt is to the approach, not the source.

## corrections

Found an endpoint that is wrong, dead, hijacked, or no longer public? Open an issue at [github.com/dharmsharmaa/dns-bench/issues](https://github.com/dharmsharmaa/dns-bench/issues) with the resolver name, the address, and what you saw. Same for a credit that is missing or misattributed — happy to fix it.

'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { run, adminShell, tcpConnect } = require('./platform');

const DIG = '/usr/bin/dig';
const PING = '/sbin/ping';
const PING6 = '/sbin/ping6';
const CURL = '/usr/bin/curl';
const NETWORKSETUP = '/usr/sbin/networksetup';
const COLD_TLDS = ['com', 'net', 'org'];
const AD_HOSTS = ['doubleclick.net', 'googleadservices.com', 'pagead2.googlesyndication.com'];
const DEFAULT_DOMAIN = 'google.com';
const SCORE_UNAVAILABLE = 99999;

// ---------------------------------------------------------------------------
// resolver catalogue (mirrors dns-bench.zsh build_resolvers)
// "Name|Kind|Region|IPv4 primary|IPv4 secondary|IPv6 primary|IPv6 secondary"
// Kind: U unfiltered | F filters content | A blocks ads | C local baseline
// ---------------------------------------------------------------------------
const RESOLVERS = [
  { name: 'Cloudflare', kind: 'U', region: 'GL', v4: ['1.1.1.1', '1.0.0.1'], v6: ['2606:4700:4700::1111', '2606:4700:4700::1001'] },
  { name: 'Cloudflare Malware', kind: 'F', region: 'GL', v4: ['1.1.1.2', '1.0.0.2'], v6: ['2606:4700:4700::1112', '2606:4700:4700::1002'] },
  { name: 'Cloudflare Family', kind: 'F', region: 'GL', v4: ['1.1.1.3', '1.0.0.3'], v6: ['2606:4700:4700::1113', '2606:4700:4700::1003'] },
  { name: 'Google Public DNS', kind: 'U', region: 'GL', v4: ['8.8.8.8', '8.8.4.4'], v6: ['2001:4860:4860::8888', '2001:4860:4860::8844'] },
  { name: 'Quad9 (Filtered)', kind: 'F', region: 'GL', v4: ['9.9.9.9', '149.112.112.112'], v6: ['2620:fe::fe', '2620:fe::9'] },
  { name: 'Quad9 (Unfiltered)', kind: 'U', region: 'GL', v4: ['9.9.9.10', '149.112.112.10'], v6: ['2620:fe::10', '2620:fe::fe:10'] },
  { name: 'Quad9 (ECS)', kind: 'F', region: 'GL', v4: ['9.9.9.11', '149.112.112.11'], v6: ['2620:fe::11', '2620:fe::fe:11'] },
  { name: 'OpenDNS Home', kind: 'F', region: 'GL', v4: ['208.67.222.222', '208.67.220.220'], v6: ['2620:119:35::35', '2620:119:53::53'] },
  { name: 'OpenDNS Family', kind: 'F', region: 'GL', v4: ['208.67.222.123', '208.67.220.123'], v6: ['2620:119:35::123', '2620:119:53::123'] },
  { name: 'AdGuard Default (ads)', kind: 'A', region: 'GL', v4: ['94.140.14.14', '94.140.15.15'], v6: ['2a10:50c0::ad1:ff', '2a10:50c0::ad2:ff'] },
  { name: 'AdGuard Family', kind: 'F', region: 'GL', v4: ['94.140.14.15', '94.140.15.16'], v6: ['2a10:50c0::bad1:ff', '2a10:50c0::bad2:ff'] },
  { name: 'AdGuard Unfiltered', kind: 'U', region: 'GL', v4: ['94.140.14.140', '94.140.14.141'], v6: ['2a10:50c0::1:ff', '2a10:50c0::2:ff'] },
  { name: 'Control D Unfiltered', kind: 'U', region: 'GL', v4: ['76.76.2.0', '76.76.10.0'], v6: ['2606:1a40::', '2606:1a40:1::'] },
  { name: 'Control D Malware', kind: 'F', region: 'GL', v4: ['76.76.2.1', '76.76.10.1'], v6: ['2606:1a40::1', '2606:1a40:1::1'] },
  { name: 'Control D Ads', kind: 'A', region: 'GL', v4: ['76.76.2.2', '76.76.10.2'], v6: ['2606:1a40::2', '2606:1a40:1::2'] },
  { name: 'NextDNS (Anycast)', kind: 'U', region: 'GL', v4: ['45.90.28.0', '45.90.30.0'], v6: ['2a07:a8c0::', '2a07:a8c1::'] },
  { name: 'Mullvad DNS', kind: 'U', region: 'EU', v4: ['194.242.2.2'], v6: ['2a07:e340::2'] },
  { name: 'Mullvad Adblock', kind: 'A', region: 'EU', v4: ['194.242.2.3'], v6: ['2a07:e340::3'] },
  { name: 'CleanBrowsing Security', kind: 'F', region: 'GL', v4: ['185.228.168.9', '185.228.169.9'], v6: ['2a0d:2a00:1::2', '2a0d:2a00:2::2'] },
  { name: 'CleanBrowsing Family', kind: 'F', region: 'GL', v4: ['185.228.168.168', '185.228.169.168'], v6: ['2a0d:2a00:1::', '2a0d:2a00:2::'] },
  { name: 'CleanBrowsing Adult Filter', kind: 'F', region: 'GL', v4: ['185.228.168.10', '185.228.169.11'], v6: ['2a0d:2a00:1::1', '2a0d:2a00:2::1'] },
  { name: 'DNS.SB', kind: 'U', region: 'GL', v4: ['185.222.222.222', '45.11.45.11'], v6: ['2a09::', '2a11::'] },
  { name: 'Comodo Secure DNS', kind: 'F', region: 'NA', v4: ['8.26.56.26', '8.20.247.20'], v6: [] },
  { name: 'Verisign Public DNS', kind: 'U', region: 'GL', v4: ['64.6.64.6', '64.6.65.6'], v6: ['2620:74:1b::1:1', '2620:74:1c::2:2'] },
  { name: 'Level3 / Lumen', kind: 'U', region: 'NA', v4: ['4.2.2.1', '4.2.2.2'], v6: [] },
  { name: 'Neustar UltraDNS', kind: 'U', region: 'GL', v4: ['156.154.70.1', '156.154.71.1'], v6: ['2610:a1:1018::1', '2610:a1:1019::1'] },
  { name: 'Hurricane Electric', kind: 'U', region: 'GL', v4: ['74.82.42.42'], v6: ['2001:470:20::2'] },
  { name: 'Alternate DNS (ads)', kind: 'A', region: 'GL', v4: ['76.76.19.19', '76.223.122.150'], v6: ['2602:fcbc::ad', '2602:fcbc:2::ad'] },
  { name: 'OpenNIC (anycast)', kind: 'U', region: 'GL', v4: ['185.121.177.177', '169.239.202.202'], v6: [] },
  { name: 'CIRA Shield Private', kind: 'U', region: 'NA', v4: ['149.112.121.10', '149.112.122.10'], v6: ['2620:10A:80BB::10', '2620:10A:80BC::10'] },
  { name: 'CIRA Shield Protected', kind: 'F', region: 'NA', v4: ['149.112.121.20', '149.112.122.20'], v6: ['2620:10A:80BB::20', '2620:10A:80BC::20'] },
  { name: 'DNS4EU (Unfiltered)', kind: 'U', region: 'EU', v4: ['86.54.11.100', '86.54.11.200'], v6: ['2a13:1001::86:54:11:100', '2a13:1001::86:54:11:200'] },
  { name: 'DNS0.eu', kind: 'F', region: 'EU', v4: ['193.110.81.0', '185.253.5.0'], v6: ['2a0f:fc80::', '2a0f:fc81::'] },
  { name: 'DNS0.eu Open', kind: 'U', region: 'EU', v4: ['193.110.81.254', '185.253.5.254'], v6: ['2a0f:fc80::254', '2a0f:fc81::254'] },
  { name: 'DNS.WATCH', kind: 'U', region: 'EU', v4: ['84.200.69.80', '84.200.70.40'], v6: ['2001:1608:10:25::1c04:b12f', '2001:1608:10:25::9249:d69b'] },
  { name: 'UncensoredDNS', kind: 'U', region: 'EU', v4: ['91.239.100.100', '89.233.43.71'], v6: ['2001:67c:28a4::', '2a01:3a0:53:53::'] },
  { name: 'Digitale Gesellschaft', kind: 'U', region: 'EU', v4: ['185.95.218.42', '185.95.218.43'], v6: ['2a02:c205:3001:4558::1', '2a02:c205:3001:4558::2'] },
  { name: 'SafeDNS', kind: 'F', region: 'EU', v4: ['195.46.39.39', '195.46.39.40'], v6: [] },
  { name: 'Yandex Basic', kind: 'U', region: 'EU', v4: ['77.88.8.8', '77.88.8.1'], v6: ['2a02:6b8::feed:0ff', '2a02:6b8:0:1::feed:0ff'] },
  { name: 'Yandex Safe', kind: 'F', region: 'EU', v4: ['77.88.8.88', '77.88.8.2'], v6: ['2a02:6b8::feed:bad', '2a02:6b8:0:1::feed:bad'] },
  { name: 'Yandex Family', kind: 'F', region: 'EU', v4: ['77.88.8.7', '77.88.8.3'], v6: ['2a02:6b8::feed:a11', '2a02:6b8:0:1::feed:a11'] },
  { name: 'Quad101 (TWNIC)', kind: 'U', region: 'AS', v4: ['101.101.101.101', '101.102.103.104'], v6: ['2001:de4::101', '2001:de4::102'] },
  { name: 'AliDNS', kind: 'U', region: 'AS', v4: ['223.5.5.5', '223.6.6.6'], v6: ['2400:3200::1', '2400:3200:baba::1'] },
  { name: 'DNSPod (Tencent)', kind: 'U', region: 'AS', v4: ['119.29.29.29', '182.254.116.116'], v6: [] },
  { name: 'Baidu DNS', kind: 'U', region: 'AS', v4: ['180.76.76.76'], v6: ['2400:da00::6666'] },
  { name: '114DNS', kind: 'U', region: 'AS', v4: ['114.114.114.114', '114.114.115.115'], v6: [] },
  { name: 'CNNIC SDNS', kind: 'U', region: 'AS', v4: ['1.2.4.8', '210.2.4.8'], v6: [] },
  { name: 'KT (Korea Telecom)', kind: 'U', region: 'AS', v4: ['168.126.63.1', '168.126.63.2'], v6: [] },
  { name: 'LG U+ (Korea)', kind: 'U', region: 'AS', v4: ['164.124.101.2', '203.248.252.2'], v6: [] },
  { name: 'SingTel (Singapore)', kind: 'U', region: 'AS', v4: ['165.21.83.88', '165.21.100.88'], v6: [] }
];

// ---------------------------------------------------------------------------
// small utilities
// ---------------------------------------------------------------------------
let cancelled = false;

function isIpv4(value) {
  if (typeof value !== 'string') return false;
  const parts = value.trim().split('.');
  if (parts.length !== 4) return false;
  return parts.every((part) => /^\d{1,3}$/.test(part) && Number(part) <= 255);
}

function isIpv6(value) {
  if (typeof value !== 'string') return false;
  const text = value.trim();
  if (!text.includes(':') || !/^[0-9a-fA-F:.]+$/.test(text)) return false;
  return (text.match(/:/g) || []).length >= 2;
}

function isIp(value) {
  return isIpv4(value) || isIpv6(value);
}

function firstLine(text) {
  return String(text || '').split('\n').map((line) => line.trim()).find(Boolean) || '';
}

function medianOf(values) {
  if (!Array.isArray(values) || !values.length) return null;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.ceil(sorted.length / 2) - 1];
}

function minOf(values) {
  return values.length ? Math.min(...values) : null;
}

function maxOf(values) {
  return values.length ? Math.max(...values) : null;
}

function round1(value) {
  return Math.round(Number(value) * 10) / 10;
}

function randomLabel() {
  return `x${Math.floor(Math.random() * 1e9)}${Math.floor(Math.random() * 1e4)}`;
}

function safeCall(fn, payload) {
  if (typeof fn !== 'function') return;
  try {
    fn(payload);
  } catch {
    /* renderer callbacks must never break a run */
  }
}

function emptyResult() {
  return { stdout: '', stderr: '', code: 1 };
}

function lastMeaningfulLines(text, count = 2) {
  return String(text || '')
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
    .slice(-count)
    .join(' ');
}

function shellQuote(value) {
  return `'${String(value).replace(/'/g, `'\\''`)}'`;
}

// ---------------------------------------------------------------------------
// network snapshot helpers
// ---------------------------------------------------------------------------
function parseDefaultRoute(stdout) {
  return {
    gateway: (stdout.match(/^\s*gateway:\s*(\S+)/m) || [])[1] || '',
    device: (stdout.match(/^\s*interface:\s*(\S+)/m) || [])[1] || ''
  };
}

function hardwarePortFor(stdout, device) {
  if (!device) return '';
  for (const block of String(stdout || '').split(/\n\s*\n/)) {
    const blockDevice = (block.match(/Device:\s*(\S+)/) || [])[1];
    if (blockDevice === device) {
      return ((block.match(/Hardware Port:\s*(.+)/) || [])[1] || '').trim();
    }
  }
  return '';
}

function parseIfconfig(stdout) {
  const text = String(stdout || '');
  const addresses = [];
  for (const line of text.split('\n')) {
    const parts = line.trim().split(/\s+/);
    if (parts[0] === 'inet6' && parts[1] && !/^fe80/i.test(parts[1])) {
      addresses.push(parts[1].split('%')[0]);
    }
  }
  return {
    mac: (text.match(/\bether\s+([0-9a-f:]{17})/i) || [])[1] || '',
    mtu: Number((text.match(/\bmtu\s+(\d+)/) || [])[1]) || null,
    link: ((text.match(/media:\s*([^\n]+)/) || [])[1] || '').trim(),
    v6: addresses
  };
}

function parseResolver1(stdout) {
  const lines = String(stdout || '').split('\n');
  const start = lines.findIndex((line) => line.trim() === 'resolver #1');
  if (start === -1) return [];
  const servers = [];
  for (let i = start + 1; i < lines.length; i += 1) {
    if (/^\s*resolver #\d+/.test(lines[i])) break;
    const match = lines[i].match(/nameserver\[\d+\]\s*:\s*(\S+)/);
    if (match) servers.push(match[1]);
  }
  return servers;
}

function parseProxy(stdout) {
  const names = [];
  for (const line of String(stdout || '').split('\n')) {
    const match = line.match(/^\s*(\w+)Enable\s*:\s*1\s*$/);
    if (match) names.push(match[1]);
  }
  return names.length ? names.join(', ') : 'none';
}

function parseVpn(stdout, device) {
  const count = String(stdout || '')
    .split('\n')
    .filter((line) => /\(Connected\)/.test(line)).length;
  if (count > 0) return `yes (${count})`;
  if (/^utun/i.test(device || '')) return 'yes (tunnel)';
  return 'no';
}

function parseWifi(stdout) {
  const match = String(stdout || '').match(/Current (?:Wi-Fi|AirPort) Network:\s*(.+)/i);
  return match ? match[1].trim() : '';
}

function parseTrace(stdout) {
  const map = {};
  for (const line of String(stdout || '').split('\n')) {
    const index = line.indexOf('=');
    if (index > 0) map[line.slice(0, index).trim()] = line.slice(index + 1).trim();
  }
  return map;
}

function parseDnsServersOutput(stdout) {
  const text = String(stdout || '').trim();
  if (!text || /aren't any|no dns servers|not set/i.test(text)) {
    return { ok: true, servers: [] };
  }
  if (/not a recognized network service|not a valid/i.test(text)) return { ok: false, servers: [] };
  const servers = text
    .split('\n')
    .map((line) => line.trim())
    .filter(isIp);
  return { ok: true, servers };
}

function modeFromServers(servers) {
  return servers.length ? `manual: ${servers.join(', ')}` : 'automatic (DHCP/router)';
}

function macOsLabel() {
  if (os.type() !== 'Darwin') return `${os.type()} ${os.release()}`;
  return `macOS ${os.release()}`;
}

async function geoInfo() {
  const who = await run(CURL, ['-4', '-s', '-m', '6', 'https://ipwho.is/'], { timeout: 8000 });
  try {
    const data = JSON.parse(who.stdout);
    if (data && data.success !== false && (data.city || data.country)) {
      const connection = data.connection || {};
      return {
        isp: connection.isp || connection.org || 'unknown',
        asn: connection.asn ? `AS${connection.asn}` : 'unknown',
        location: [data.city, data.region, data.country].filter(Boolean).join(', ') || 'unknown',
        timezone: (data.timezone && data.timezone.id) || ''
      };
    }
  } catch {
    /* fall through to the secondary provider */
  }

  const info = await run(CURL, ['-4', '-s', '-m', '6', 'https://ipinfo.io/json'], { timeout: 8000 });
  try {
    const data = JSON.parse(info.stdout);
    if (data && (data.city || data.country)) {
      const org = String(data.org || '');
      return {
        isp: org.replace(/^AS\d+\s*/, '') || 'unknown',
        asn: (org.match(/^AS\d+/) || [])[0] || 'unknown',
        location: [data.city, data.region, data.country].filter(Boolean).join(', ') || 'unknown',
        timezone: data.timezone || ''
      };
    }
  } catch {
    /* geo is best effort */
  }
  return null;
}

// ---------------------------------------------------------------------------
// network snapshot
// ---------------------------------------------------------------------------
async function getNetworkInfo() {
  const info = {
    host: os.hostname(),
    os: macOsLabel(),
    arch: os.arch(),
    interface: 'unknown',
    service: 'unknown',
    link: '',
    mac: '',
    mtu: null,
    localIPv4: '',
    localIPv6: [],
    gateway: '',
    gatewayMs: null,
    gatewayLoss: null,
    publicIP: 'unknown',
    publicIP6: 'unknown',
    isp: 'unknown',
    asn: 'unknown',
    location: 'unknown',
    timezone: '',
    pop: 'unknown',
    warp: 'unknown',
    dnsInUse: [],
    dnsSource: 'unknown',
    vpn: 'no',
    proxy: 'none',
    v6: false,
    wifi: '',
    captive: 'unknown',
    intercept: 'unknown',
    egress: 'unknown'
  };

  try {
    info.timezone = Intl.DateTimeFormat().resolvedOptions().timeZone || '';
  } catch {
    info.timezone = '';
  }

  try {
    const [routeRes, portsRes, dnsRes, ncRes, proxyRes, versionRes] = await Promise.all([
      run('/sbin/route', ['-n', 'get', 'default'], { timeout: 4000 }),
      run(NETWORKSETUP, ['-listallhardwareports'], { timeout: 4000 }),
      run('/usr/sbin/scutil', ['--dns'], { timeout: 4000 }),
      run('/usr/sbin/scutil', ['--nc', 'list'], { timeout: 4000 }),
      run('/usr/sbin/scutil', ['--proxy'], { timeout: 4000 }),
      run('/usr/bin/sw_vers', ['-productVersion'], { timeout: 3000 })
    ]);

    const route = parseDefaultRoute(routeRes.stdout);
    const device = route.device;
    const port = hardwarePortFor(portsRes.stdout, device);
    const version = firstLine(versionRes.stdout);

    info.interface = device || 'unknown';
    info.service = port || device || 'unknown';
    info.gateway = route.gateway;
    info.vpn = parseVpn(ncRes.stdout, device);
    info.proxy = parseProxy(proxyRes.stdout);
    info.dnsInUse = parseResolver1(dnsRes.stdout);
    if (os.type() === 'Darwin' && version) info.os = `macOS ${version}`;

    const [ifconfigRes, ipv4Res, wifiRes, dnsModeRes, pingRes, trace4Res, trace6Res, geo, captiveRes, interceptRes, egressRes, v6Res] = await Promise.all([
      device ? run('/sbin/ifconfig', [device], { timeout: 4000 }) : Promise.resolve(emptyResult()),
      device ? run('/usr/sbin/ipconfig', ['getifaddr', device], { timeout: 4000 }) : Promise.resolve(emptyResult()),
      device ? run(NETWORKSETUP, ['-getairportnetwork', device], { timeout: 4000 }) : Promise.resolve(emptyResult()),
      info.service !== 'unknown' ? run(NETWORKSETUP, ['-getdnsservers', info.service], { timeout: 5000 }) : Promise.resolve(emptyResult()),
      isIpv4(route.gateway) ? run(PING, ['-c', '3', '-t', '3', route.gateway], { timeout: 6000 }) : Promise.resolve(emptyResult()),
      run(CURL, ['-4', '-s', '-m', '5', 'https://1.1.1.1/cdn-cgi/trace'], { timeout: 7000 }),
      run(CURL, ['-6', '-g', '-s', '-m', '5', 'https://[2606:4700:4700::1111]/cdn-cgi/trace'], { timeout: 7000 }),
      geoInfo(),
      run(CURL, ['-s', '-m', '4', 'http://captive.apple.com/'], { timeout: 6000 }),
      run(DIG, ['@192.0.2.53', 'example.com', '+short', '+time=2', '+tries=1'], { timeout: 5000 }),
      run(DIG, ['+short', 'whoami.akamai.net', '+time=2', '+tries=1'], { timeout: 5000 }),
      run(DIG, ['@2606:4700:4700::1111', 'example.com', 'A', '+short', '+time=2', '+tries=1'], { timeout: 6000 })
    ]);

    const iface = parseIfconfig(ifconfigRes.stdout);
    info.link = iface.link;
    info.mac = iface.mac;
    info.mtu = iface.mtu;
    info.localIPv6 = iface.v6;
    info.localIPv4 = isIpv4(firstLine(ipv4Res.stdout)) ? firstLine(ipv4Res.stdout) : '';
    info.wifi = parseWifi(wifiRes.stdout);

    const dnsMode = parseDnsServersOutput(dnsModeRes.stdout);
    info.dnsSource = dnsModeRes.code === 0 && dnsMode.ok ? modeFromServers(dnsMode.servers) : 'unknown';

    const ping = parsePingOutput(pingRes.stdout);
    info.gatewayMs = ping.avg;
    info.gatewayLoss = ping.loss;

    const trace4 = parseTrace(trace4Res.stdout);
    const trace6 = parseTrace(trace6Res.stdout);
    info.publicIP = trace4.ip || 'unknown';
    info.publicIP6 = trace6.ip || 'unknown';
    info.pop = trace4.colo || 'unknown';
    info.warp = trace4.warp || 'unknown';
    if (info.publicIP === 'unknown') {
      const fallback = await run(DIG, ['+short', 'myip.opendns.com', '@resolver1.opendns.com', '+time=2', '+tries=1'], { timeout: 5000 });
      const candidate = firstLine(fallback.stdout);
      if (isIp(candidate)) info.publicIP = candidate;
    }

    if (geo) {
      info.isp = geo.isp;
      info.asn = geo.asn;
      info.location = geo.location;
      if (geo.timezone) info.timezone = geo.timezone;
    }

    info.captive = /Success/i.test(captiveRes.stdout) ? 'no' : 'possible';
    info.intercept = hasDigAnswer(interceptRes.stdout) ? 'yes' : 'none';
    const egress = firstLine(egressRes.stdout);
    info.egress = isIp(egress) ? egress : 'unknown';
    info.v6 = hasDigAnswer(v6Res.stdout);
  } catch {
    return info;
  }

  return info;
}

function parsePingOutput(stdout) {
  const text = String(stdout || '');
  const lossMatch = text.match(/([0-9.]+)% packet loss/);
  const avgMatch = text.match(/min\/avg\/max(?:\/std-?dev)?\s*=\s*[0-9.]+\/([0-9.]+)\//);
  return {
    avg: avgMatch ? round1(Number(avgMatch[1])) : null,
    loss: lossMatch ? Number(lossMatch[1]) : null
  };
}

function hasDigAnswer(stdout) {
  return String(stdout || '')
    .split('\n')
    .map((line) => line.trim())
    .some((line) => line && !line.startsWith(';') && !/timed out|no servers|could be reached|communications error/i.test(line));
}

// ---------------------------------------------------------------------------
// active service / DNS status
// ---------------------------------------------------------------------------
async function activeNetworkService() {
  const [routeRes, portsRes] = await Promise.all([
    run('/sbin/route', ['-n', 'get', 'default'], { timeout: 4000 }),
    run(NETWORKSETUP, ['-listallhardwareports'], { timeout: 4000 })
  ]);
  const { device, gateway } = parseDefaultRoute(routeRes.stdout);
  const port = hardwarePortFor(portsRes.stdout, device);
  return { device, gateway, service: port || device || '' };
}

async function manualDnsServers(service) {
  if (!service) return { ok: false, servers: [] };
  const result = await run(NETWORKSETUP, ['-getdnsservers', service], { timeout: 5000 });
  if (result.code !== 0) return { ok: false, servers: [] };
  return parseDnsServersOutput(result.stdout);
}

async function systemDnsServers() {
  const result = await run('/usr/sbin/scutil', ['--dns'], { timeout: 4000 });
  return parseResolver1(result.stdout);
}

async function getDnsStatus() {
  try {
    const { service } = await activeNetworkService();
    const manual = await manualDnsServers(service);
    if (manual.ok && manual.servers.length) {
      return { mode: modeFromServers(manual.servers), servers: manual.servers, service: service || 'unknown' };
    }
    const servers = await systemDnsServers();
    return { mode: manual.ok ? 'automatic (DHCP/router)' : 'unknown', servers, service: service || 'unknown' };
  } catch {
    return { mode: 'unknown', servers: [], service: 'unknown' };
  }
}

// ---------------------------------------------------------------------------
// resolver list
// ---------------------------------------------------------------------------
async function gatewayAnswersDns(gateway) {
  if (!isIpv4(gateway)) return false;
  const result = await run(DIG, [`@${gateway}`, 'example.com', '+short', '+time=1', '+tries=1'], { timeout: 4000 });
  return hasDigAnswer(result.stdout);
}

async function buildResolvers() {
  const network = await getNetworkInfo();
  const resolvers = RESOLVERS.map((resolver) => ({
    name: resolver.name,
    kind: resolver.kind,
    region: resolver.region,
    v4: [...resolver.v4],
    v6: [...resolver.v6]
  }));

  if (isIpv4(network.gateway) && (await gatewayAnswersDns(network.gateway))) {
    resolvers.push({ name: 'Router / Gateway', kind: 'C', region: 'LAN', v4: [network.gateway], v6: [] });
  }

  const systemDns = (network.dnsInUse || []).find((server) => isIpv4(server) && server !== network.gateway);
  if (systemDns) {
    resolvers.push({ name: 'Current system DNS', kind: 'C', region: 'LAN', v4: [systemDns], v6: [] });
  }

  return {
    resolvers: resolvers.map((resolver, index) => ({ ...resolver, index: index + 1 })),
    network
  };
}

// ---------------------------------------------------------------------------
// probes
// ---------------------------------------------------------------------------
function parseDig(stdout) {
  const text = String(stdout || '');
  const status = (text.match(/status:\s*([A-Z]+)/) || [])[1] || '';
  const time = text.match(/Query time:\s*(\d+)/);
  const answer = text.match(/ANSWER:\s*(\d+)/);
  return {
    status,
    ms: time ? Number(time[1]) : null,
    answers: answer ? Number(answer[1]) : 0
  };
}

async function dig(server, name, extra = [], timeout = 8000) {
  return run(DIG, [`@${server}`, name, ...extra], { timeout });
}

async function cachedStats(server, samples, domain, stopped) {
  const times = [];
  let failures = 0;
  for (let i = 0; i <= samples; i += 1) {
    if (stopped()) break;
    const reply = parseDig((await dig(server, domain, ['A', '+tries=1', '+time=2', '+stats'], 6000)).stdout);
    if (i === 0) continue; // first query is a warm-up, never counted
    if (reply.status === 'NOERROR' && reply.answers > 0 && reply.ms !== null) times.push(reply.ms);
    else failures += 1;
  }
  return {
    median: medianOf(times),
    min: minOf(times),
    max: maxOf(times),
    loss: Math.round((failures * 100) / Math.max(1, samples))
  };
}

async function coldStats(server, stopped) {
  const times = [];
  for (let i = 0; i < COLD_TLDS.length; i += 1) {
    if (stopped()) break;
    const name = `${randomLabel()}.${COLD_TLDS[i]}`;
    const reply = parseDig((await dig(server, name, ['A', '+tries=1', '+time=2', '+stats'], 6000)).stdout);
    const valid = reply.status === 'NXDOMAIN' || reply.status === 'NOERROR';
    if (valid && reply.ms !== null) times.push(reply.ms);
  }
  return { median: medianOf(times) };
}

async function queryStatus(server, name, time = 3) {
  const reply = parseDig((await dig(server, name, ['A', '+tries=1', `+time=${time}`], 8000)).stdout);
  return reply.status;
}

async function checkDnssec(server) {
  const [ok, bad] = await Promise.all([
    queryStatus(server, 'sigok.verteiltesysteme.net'),
    queryStatus(server, 'sigfail.verteiltesysteme.net')
  ]);
  if (ok === 'NOERROR' && bad === 'SERVFAIL') return 'yes';
  if (ok === 'NOERROR' && bad === 'NOERROR') return 'no';
  return '?';
}

async function checkHijack(server) {
  const status = await queryStatus(server, `${randomLabel()}.com`);
  if (status === 'NXDOMAIN') return 'ok';
  if (status === 'NOERROR') return 'HIJACK';
  return '?';
}

async function checkTcp(server, domain) {
  const reply = parseDig((await dig(server, domain, ['A', '+tcp', '+tries=1', '+time=3'], 8000)).stdout);
  return reply.status === 'NOERROR' ? 'yes' : 'no';
}

async function checkAds(server) {
  let seen = 0;
  let blocked = 0;
  for (const host of AD_HOSTS) {
    if (cancelled) break;
    const result = await dig(server, host, ['A', '+tries=1', '+time=3'], 8000);
    const text = result.stdout;
    if (!text || /timed out/i.test(text)) continue;
    seen += 1;
    const reply = parseDig(text);
    const answer = firstAnswerIp(text);
    const nullRouted = /^(0\.0\.0\.0|127\.|146\.112\.61\.)/.test(answer);
    if (reply.status === 'NXDOMAIN' || reply.status === 'REFUSED' || nullRouted || (!answer && reply.status === 'NOERROR')) {
      blocked += 1;
    }
  }
  if (seen === 0) return '?';
  return blocked * 2 > seen ? 'yes' : 'no';
}

function firstAnswerIp(stdout) {
  for (const line of String(stdout || '').split('\n')) {
    if (!line || line.startsWith(';')) continue;
    const parts = line.trim().split(/\s+/);
    if (parts[2] === 'IN' && parts[3] === 'A') return parts[4] || '';
  }
  return '';
}

async function checkPop(server, name) {
  if (/^OpenDNS/i.test(name)) {
    const result = await dig(server, 'debug.opendns.com', ['TXT', '+short', '+tries=1', '+time=2'], 6000);
    const line = String(result.stdout)
      .split('\n')
      .map((entry) => entry.replace(/"/g, '').trim())
      .find((entry) => entry.startsWith('server '));
    if (line) return sanitizePop(line.split(/\s+/)[1]);
  }

  for (const query of ['id.server', 'hostname.bind']) {
    if (cancelled) break;
    const result = await dig(server, query, ['CH', 'TXT', '+short', '+tries=1', '+time=2'], 6000);
    const line = String(result.stdout)
      .split('\n')
      .map((entry) => entry.replace(/"/g, '').trim())
      .find((entry) => entry && !entry.startsWith(';') && !/timed out/i.test(entry));
    if (line) return sanitizePop(line);
  }
  return '-';
}

function sanitizePop(value) {
  const clean = String(value || '').trim().split(/\s+/)[0].replace(/\|/g, '_');
  return clean ? clean.slice(0, 22) : '-';
}

async function pingStats(ip, tool = PING, args = ['-c', '3', '-t', '2']) {
  const result = await run(tool, [...args, ip], { timeout: 6000 });
  return parsePingOutput(result.stdout);
}

function baseRow(resolver, index, hasV6) {
  return {
    index,
    name: resolver.name,
    kind: resolver.kind,
    region: resolver.region,
    cached: 'Timeout',
    jitter: null,
    loss: 100,
    cold: null,
    score: SCORE_UNAVAILABLE,
    v4ping: null,
    v6dns: 'N/A',
    v6ping: null,
    dnssec: '?',
    nx: '?',
    tcp: '?',
    dot: '?',
    doh: '?',
    ads: '?',
    pop: '-',
    servers: [...resolver.v4, ...(hasV6 ? resolver.v6 : [])]
  };
}

async function probeResolver(resolver, options) {
  const { index, samples, domain, hasV6, stopped } = options;
  const row = baseRow(resolver, index, hasV6);
  const primary = resolver.v4[0] || resolver.v6[0];
  if (!primary || stopped()) return row;

  const cached = await cachedStats(primary, samples, domain, stopped);
  row.cached = cached.median === null ? 'Timeout' : cached.median;
  row.loss = cached.loss;
  if (cached.median === null) return row; // dead resolver: skip the expensive feature checks

  row.jitter = cached.max !== null && cached.min !== null ? cached.max - cached.min : null;

  const v6Target = hasV6 && resolver.v6.length ? (resolver.v6[0] || '') : '';
  const [cold, v4ping, dnssec, nx, tcp, dot, doh, ads, pop, v6dns, v6ping] = await Promise.all([
    stopped() ? Promise.resolve({ median: null }) : coldStats(primary, stopped),
    stopped() ? Promise.resolve({ avg: null }) : pingStats(primary),
    stopped() ? Promise.resolve('?') : checkDnssec(primary),
    stopped() ? Promise.resolve('?') : checkHijack(primary),
    stopped() ? Promise.resolve('?') : checkTcp(primary, domain),
    stopped() ? Promise.resolve('?') : tcpConnect(primary, 853, 3000).then((ms) => (ms === null ? 'no' : 'yes')),
    stopped() ? Promise.resolve('?') : tcpConnect(primary, 443, 3000).then((ms) => (ms === null ? 'no' : 'yes')),
    stopped() ? Promise.resolve('?') : checkAds(primary),
    stopped() ? Promise.resolve('-') : checkPop(primary, resolver.name),
    v6Target && !stopped() ? cachedStats(v6Target, 3, domain, stopped) : Promise.resolve({ median: null }),
    v6Target && !stopped() ? pingStats(v6Target, PING6, ['-c', '3']) : Promise.resolve({ avg: null })
  ]);

  row.cold = cold.median;
  row.v4ping = v4ping.avg;
  row.dnssec = dnssec;
  row.nx = nx;
  row.tcp = tcp;
  row.dot = dot;
  row.doh = doh;
  row.ads = ads;
  row.pop = pop;
  if (v6Target) {
    row.v6dns = v6dns.median === null ? 'Timeout' : v6dns.median;
    row.v6ping = v6ping.avg;
  }

  const base = row.cold !== null
    ? (row.cached + 2 * row.cold) / 3
    : row.cached * 3;
  row.score = round1(base + 3 * row.loss);
  return row;
}

async function ipv6Works() {
  const result = await run(DIG, ['@2606:4700:4700::1111', 'example.com', 'A', '+short', '+tries=1', '+time=2'], { timeout: 6000 });
  return hasDigAnswer(result.stdout);
}

// ---------------------------------------------------------------------------
// benchmark orchestration
// ---------------------------------------------------------------------------
async function runBenchmark(options = {}) {
  cancelled = false;

  const list = Array.isArray(options.resolvers) && options.resolvers.length ? options.resolvers : RESOLVERS;
  const samples = Math.min(20, Math.max(1, Number(options.samples) || 5));
  const domain = String(options.domain || DEFAULT_DOMAIN).trim() || DEFAULT_DOMAIN;
  const limit = Math.min(64, Math.max(1, Number(options.concurrency) || 12));
  const onProgress = options.onProgress;
  const onResult = options.onResult;
  const isCancelled = options.isCancelled;

  const stopped = () => cancelled || (typeof isCancelled === 'function' && Boolean(isCancelled()));
  const total = list.length;
  const rows = new Array(total);
  let done = 0;
  let cursor = 0;

  let hasV6 = false;
  if (list.some((resolver) => Array.isArray(resolver.v6) && resolver.v6.length)) {
    hasV6 = await ipv6Works();
  }

  const report = (label, phase) => safeCall(onProgress, { done, total, label, phase });

  const worker = async () => {
    while (!stopped()) {
      const slot = cursor;
      cursor += 1;
      if (slot >= total) return;

      const resolver = list[slot];
      const index = Number.isFinite(Number(resolver.index)) ? Number(resolver.index) : slot + 1;
      report(resolver.name, 'probing');

      let row;
      try {
        row = await probeResolver(resolver, { index, samples, domain, hasV6, stopped });
      } catch {
        row = baseRow(resolver, index, hasV6);
      }

      rows[slot] = row;
      done += 1;
      safeCall(onResult, row);
      report(resolver.name, 'done');
    }
  };

  const workers = Array.from({ length: Math.min(limit, Math.max(1, total)) }, () => worker());
  await Promise.all(workers);

  return rows.filter(Boolean).sort((a, b) => a.index - b.index);
}

function cancel() {
  cancelled = true;
}

// ---------------------------------------------------------------------------
// apply / reset
// ---------------------------------------------------------------------------
function failureMessage(result) {
  const combined = `${result.stderr || ''} ${result.stdout || ''}`;
  if (result.code === 124) return 'Administrator authorization timed out.';
  if (/User canceled|-128/i.test(combined)) return 'Administrator authorization was canceled.';
  const detail = lastMeaningfulLines(combined);
  return detail ? `Could not change DNS: ${detail}` : 'Could not change DNS (unknown error).';
}

async function backupDnsSetting(service, device) {
  try {
    const status = await getDnsStatus();
    const line = `${new Date().toISOString()} service=${service}${device ? ` dev=${device}` : ''} mode=${status.mode} in_use=${status.servers.join(',')}\n`;
    await fs.promises.appendFile(path.join(os.homedir(), '.dns-bench-previous.txt'), line, 'utf8');
  } catch {
    /* a failed backup must not block the change */
  }
}

function flushCommand() {
  return '/usr/bin/dscacheutil -flushcache && /usr/bin/killall -HUP mDNSResponder';
}

async function applyResolver(resolver, options = {}) {
  const servers = [];
  try {
    if (!resolver || typeof resolver !== 'object') {
      return { ok: false, message: 'Unknown resolver.', servers };
    }
    const hasV6 = Boolean(options && options.hasV6);
    for (const server of resolver.v4 || []) {
      if (isIpv4(server)) servers.push(server);
    }
    if (hasV6) {
      for (const server of resolver.v6 || []) {
        if (isIpv6(server)) servers.push(server);
      }
    }
    if (!servers.length) {
      return { ok: false, message: 'This resolver has no servers usable on this network.', servers };
    }

    const { service, device } = await activeNetworkService();
    if (!service) return { ok: false, message: 'Could not determine the active network service.', servers };

    await backupDnsSetting(service, device);
    const command = `${NETWORKSETUP} -setdnsservers ${shellQuote(service)} ${servers.map(shellQuote).join(' ')} && ${flushCommand()}`;
    const result = await adminShell(command);

    if (result.code !== 0) {
      return { ok: false, message: failureMessage(result), servers };
    }
    return {
      ok: true,
      message: `DNS set to ${resolver.name} (${servers.join(', ')}) on ${service}.`,
      servers
    };
  } catch (error) {
    return { ok: false, message: error.message || 'Could not change DNS.', servers };
  }
}

async function resetDNS() {
  try {
    const { service } = await activeNetworkService();
    if (!service) return { ok: false, message: 'Could not determine the active network service.' };

    const command = `${NETWORKSETUP} -setdnsservers ${shellQuote(service)} Empty && ${flushCommand()}`;
    const result = await adminShell(command);
    if (result.code !== 0) {
      return { ok: false, message: failureMessage(result).replace('change DNS', 'reset DNS') };
    }
    return { ok: true, message: `DNS reset to automatic (DHCP/router) on ${service}.` };
  } catch (error) {
    return { ok: false, message: error.message || 'Could not reset DNS.' };
  }
}

module.exports = {
  RESOLVERS,
  buildResolvers,
  getNetworkInfo,
  runBenchmark,
  cancel,
  applyResolver,
  resetDNS,
  getDnsStatus
};

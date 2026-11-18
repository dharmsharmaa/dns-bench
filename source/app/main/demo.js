'use strict';

/*
 * Demo fixtures for `--demo`.
 * Everything here is static: no probes, no DNS changes, no user paths.
 * Addresses use the documentation ranges (192.0.2.0/24, 203.0.113.0/24,
 * 2001:db8::/32) wherever a local or public address is shown.
 */

const network = {
  host: 'demo-mac',
  os: 'macOS 15.3',
  arch: 'arm64',
  interface: 'en0',
  service: 'Wi-Fi',
  link: '866 Mb/s',
  mac: '02:00:00:00:00:01',
  mtu: 1500,
  localIPv4: '192.0.2.42',
  localIPv6: ['2001:db8:4::42'],
  gateway: '192.0.2.1',
  gatewayMs: 3.1,
  gatewayLoss: 0,
  publicIP: '203.0.113.42',
  publicIP6: '2001:db8:4::42',
  isp: 'Example ISP',
  asn: 'AS64500',
  location: 'Amsterdam, North Holland, Netherlands',
  timezone: 'Europe/Amsterdam',
  pop: 'AMS',
  warp: 'off',
  dnsInUse: ['1.1.1.1', '1.0.0.1'],
  dnsSource: 'automatic (DHCP/router)',
  vpn: 'no',
  proxy: 'none',
  v6: true,
  wifi: 'Demo Network',
  captive: 'no',
  intercept: 'none',
  egress: '203.0.113.42',
  continents: [
    { region: 'North America', city: 'N. Virginia', ms: 86 },
    { region: 'North America', city: 'Oregon', ms: 142 },
    { region: 'Europe', city: 'Ireland', ms: 12 },
    { region: 'Europe', city: 'Frankfurt', ms: 9 },
    { region: 'Europe', city: 'Stockholm', ms: 24 },
    { region: 'Middle East', city: 'Bahrain', ms: 98 },
    { region: 'Africa', city: 'Cape Town', ms: 158 },
    { region: 'Asia', city: 'Mumbai', ms: 118 },
    { region: 'Asia', city: 'Singapore', ms: 164 },
    { region: 'Asia', city: 'Tokyo', ms: 232 },
    { region: 'Oceania', city: 'Sydney', ms: 271 }
  ]
};

const resolvers = [
  {
    index: 1,
    name: 'Cloudflare',
    kind: 'U',
    region: 'GL',
    v4: ['1.1.1.1', '1.0.0.1'],
    v6: ['2606:4700:4700::1111', '2606:4700:4700::1001']
  },
  {
    index: 3,
    name: 'Cloudflare Family',
    kind: 'F',
    region: 'GL',
    v4: ['1.1.1.3', '1.0.0.3'],
    v6: ['2606:4700:4700::1113', '2606:4700:4700::1003']
  },
  {
    index: 4,
    name: 'Google Public DNS',
    kind: 'U',
    region: 'GL',
    v4: ['8.8.8.8', '8.8.4.4'],
    v6: ['2001:4860:4860::8888', '2001:4860:4860::8844']
  },
  {
    index: 5,
    name: 'Quad9 (Filtered)',
    kind: 'F',
    region: 'GL',
    v4: ['9.9.9.9', '149.112.112.112'],
    v6: ['2620:fe::fe', '2620:fe::9']
  },
  {
    index: 6,
    name: 'Quad9 (Unfiltered)',
    kind: 'U',
    region: 'GL',
    v4: ['9.9.9.10', '149.112.112.10'],
    v6: ['2620:fe::10', '2620:fe::fe:10']
  },
  {
    index: 10,
    name: 'AdGuard Default (ads)',
    kind: 'A',
    region: 'GL',
    v4: ['94.140.14.14', '94.140.15.15'],
    v6: ['2a10:50c0::ad1:ff', '2a10:50c0::ad2:ff']
  },
  {
    index: 11,
    name: 'AdGuard Unfiltered',
    kind: 'U',
    region: 'GL',
    v4: ['94.140.14.140', '94.140.14.141'],
    v6: ['2a10:50c0::1:ff', '2a10:50c0::2:ff']
  },
  {
    index: 12,
    name: 'Control D Unfiltered',
    kind: 'U',
    region: 'GL',
    v4: ['76.76.2.0', '76.76.10.0'],
    v6: ['2606:1a40::', '2606:1a40:1::']
  },
  {
    index: 15,
    name: 'NextDNS (Anycast)',
    kind: 'U',
    region: 'GL',
    v4: ['45.90.28.0', '45.90.30.0'],
    v6: ['2a07:a8c0::', '2a07:a8c1::']
  },
  {
    index: 23,
    name: 'Verisign Public DNS',
    kind: 'U',
    region: 'GL',
    v4: ['64.6.64.6', '64.6.65.6'],
    v6: ['2620:74:1b::1:1', '2620:74:1c::2:2']
  },
  {
    index: 51,
    name: 'Router / Gateway',
    kind: 'C',
    region: 'LAN',
    v4: ['192.0.2.1'],
    v6: []
  },
  {
    index: 52,
    name: 'Current system DNS',
    kind: 'C',
    region: 'LAN',
    v4: ['1.1.1.1', '1.0.0.1'],
    v6: []
  }
];

// Sorted by score ascending, exactly as the renderer expects a finished run.
const rows = [
  {
    index: 1,
    name: 'Cloudflare',
    kind: 'U',
    region: 'GL',
    cached: 14,
    jitter: 1.2,
    loss: 0,
    cold: 31,
    score: 22.0,
    v4ping: 12.4,
    v6dns: 15,
    v6ping: 12.8,
    dnssec: 'yes',
    nx: 'ok',
    tcp: 'yes',
    dot: 'yes',
    doh: 'yes',
    ads: 'no',
    pop: 'ams',
    servers: ['1.1.1.1', '1.0.0.1', '2606:4700:4700::1111']
  },
  {
    index: 52,
    name: 'Current system DNS',
    kind: 'C',
    region: 'LAN',
    cached: 14,
    jitter: 1.5,
    loss: 0,
    cold: 36,
    score: 23.0,
    v4ping: 12.6,
    v6dns: 15,
    v6ping: 12.9,
    dnssec: 'yes',
    nx: 'ok',
    tcp: 'yes',
    dot: 'yes',
    doh: 'yes',
    ads: 'no',
    pop: 'ams',
    servers: ['1.1.1.1', '1.0.0.1']
  },
  {
    index: 4,
    name: 'Google Public DNS',
    kind: 'U',
    region: 'GL',
    cached: 16,
    jitter: 1.8,
    loss: 0,
    cold: 34,
    score: 24.7,
    v4ping: 13.1,
    v6dns: 17,
    v6ping: 13.5,
    dnssec: 'yes',
    nx: 'ok',
    tcp: 'yes',
    dot: 'yes',
    doh: 'yes',
    ads: 'no',
    pop: 'ams01',
    servers: ['8.8.8.8', '8.8.4.4']
  },
  {
    index: 6,
    name: 'Quad9 (Unfiltered)',
    kind: 'U',
    region: 'GL',
    cached: 18,
    jitter: 2.1,
    loss: 0,
    cold: 38,
    score: 27.3,
    v4ping: 14.6,
    v6dns: 19,
    v6ping: 14.9,
    dnssec: 'yes',
    nx: 'ok',
    tcp: 'yes',
    dot: 'yes',
    doh: 'yes',
    ads: 'no',
    pop: 'ams',
    servers: ['9.9.9.10', '149.112.112.10']
  },
  {
    index: 11,
    name: 'AdGuard Unfiltered',
    kind: 'U',
    region: 'GL',
    cached: 21,
    jitter: 2.6,
    loss: 0,
    cold: 44,
    score: 31.7,
    v4ping: 15.2,
    v6dns: 22,
    v6ping: 15.6,
    dnssec: 'yes',
    nx: 'ok',
    tcp: 'yes',
    dot: 'yes',
    doh: 'yes',
    ads: 'no',
    pop: 'ams',
    servers: ['94.140.14.140', '94.140.14.141']
  },
  {
    index: 12,
    name: 'Control D Unfiltered',
    kind: 'U',
    region: 'GL',
    cached: 23,
    jitter: 3.0,
    loss: 0,
    cold: 47,
    score: 34.3,
    v4ping: 16.8,
    v6dns: 24,
    v6ping: 17.1,
    dnssec: 'yes',
    nx: 'ok',
    tcp: 'yes',
    dot: 'yes',
    doh: 'yes',
    ads: 'no',
    pop: 'ams',
    servers: ['76.76.2.0', '76.76.10.0']
  },
  {
    index: 15,
    name: 'NextDNS (Anycast)',
    kind: 'U',
    region: 'GL',
    cached: 27,
    jitter: 3.4,
    loss: 0,
    cold: 52,
    score: 38.7,
    v4ping: 17.9,
    v6dns: 28,
    v6ping: 18.2,
    dnssec: 'yes',
    nx: 'ok',
    tcp: 'yes',
    dot: 'yes',
    doh: 'yes',
    ads: 'no',
    pop: 'ams',
    servers: ['45.90.28.0', '45.90.30.0']
  },
  {
    index: 23,
    name: 'Verisign Public DNS',
    kind: 'U',
    region: 'GL',
    cached: 31,
    jitter: 4.1,
    loss: 0,
    cold: 58,
    score: 43.7,
    v4ping: 19.4,
    v6dns: 31,
    v6ping: 19.8,
    dnssec: 'yes',
    nx: 'ok',
    tcp: 'yes',
    dot: 'no',
    doh: 'yes',
    ads: 'no',
    pop: '-',
    servers: ['64.6.64.6', '64.6.65.6']
  },
  {
    index: 51,
    name: 'Router / Gateway',
    kind: 'C',
    region: 'LAN',
    cached: 2.4,
    jitter: 0.6,
    loss: 0,
    cold: 39,
    score: 68.8,
    v4ping: 1.9,
    v6dns: '-',
    v6ping: 1.8,
    dnssec: '?',
    nx: 'ok',
    tcp: 'yes',
    dot: 'no',
    doh: 'yes',
    ads: 'no',
    pop: '-',
    servers: ['192.0.2.1']
  }
];

const history = [
  {
    id: 1,
    at: new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString(),
    best: 'Cloudflare',
    score: 22.0,
    count: 9,
    durationMs: 21400,
    rows
  }
];

const settings = {
  samples: 5,
  domain: 'example.com',
  concurrency: 12,
  autoExport: false,
  v6: true
};

module.exports = { network, resolvers, rows, history, settings };

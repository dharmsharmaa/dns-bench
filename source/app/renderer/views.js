'use strict';

/*
 * DNS Bench renderer views.
 * Pure functions: state in, HTML string out. No DOM, no modules.
 */
(function () {
  var KIND = { U: 'Unfiltered', F: 'Filtered', A: 'Ads blocked', C: 'Current DNS' };
  var KIND_SHORT = { U: 'Unfiltered', F: 'Filtered', A: 'Ad-block', C: 'Current DNS' };
  var REGION = {
    GL: 'Global anycast',
    NA: 'North America',
    SA: 'South America',
    EU: 'Europe',
    AS: 'Asia',
    OC: 'Oceania',
    AF: 'Africa',
    LAN: 'Local network'
  };
  var MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  var FILTERS = [
    { key: 'all', label: 'All' },
    { key: 'U', label: 'Unfiltered' },
    { key: 'F', label: 'Filtered' },
    { key: 'A', label: 'Ads' },
    { key: 'C', label: 'Current' }
  ];
  var SCREENS = [
    { key: 'overview', label: 'Overview', icon: 'gauge' },
    { key: 'benchmark', label: 'Benchmark', icon: 'list' },
    { key: 'network', label: 'Network', icon: 'globe' },
    { key: 'history', label: 'History', icon: 'clock' },
    { key: 'settings', label: 'Settings', icon: 'gear' }
  ];

  // -------------------------------------------------------------------------
  // primitives
  // -------------------------------------------------------------------------
  function esc(value) {
    if (value === null || value === undefined) return '';
    return String(value)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function icon(name, size) {
    return window.Icons && window.Icons.icon ? window.Icons.icon(name, size) : '';
  }

  function logo(size) {
    return window.Icons && window.Icons.logo ? window.Icons.logo(size) : '';
  }

  function num(value) {
    if (typeof value === 'number') return Number.isFinite(value) ? value : null;
    if (typeof value === 'string') {
      var text = value.trim();
      if (!text || text === '-' || text === '—' || text === 'N/A' || text === 'Timeout') return null;
      var n = Number(text);
      return Number.isFinite(n) ? n : null;
    }
    return null;
  }

  function fmtMs(value, opts) {
    opts = opts || {};
    if (value === null || value === undefined || value === '') return '—';
    if (typeof value === 'string') {
      var raw = value.trim();
      if (!raw) return '—';
      if (raw === 'Timeout' || raw === 'N/A') return raw;
      if (raw === '-' || raw === '—') return '—';
    }
    var ms = num(value);
    if (ms === null) return typeof value === 'string' ? esc(value) : '—';
    if (ms < 0) return '—';
    if (ms >= 1000) {
      var seconds = ms / 1000;
      var secDigits = opts.digits !== undefined ? opts.digits : seconds >= 10 ? 0 : 1;
      return seconds.toFixed(secDigits) + ' s';
    }
    var digits = opts.digits !== undefined ? opts.digits : ms < 10 ? 1 : 0;
    return ms.toFixed(digits) + ' ms';
  }

  function fmtScore(value) {
    var n = num(value);
    if (n === null || n >= 99999) return '—';
    return n.toFixed(1);
  }

  function fmtPct(value) {
    var n = num(value);
    if (n === null) return '—';
    return Math.round(n * 10) / 10 + '%';
  }

  function clampInt(value, min, max, fallback) {
    var n = num(value);
    if (n === null) return fallback;
    return Math.min(max, Math.max(min, Math.round(n)));
  }

  function clampPct(value) {
    return Math.max(0, Math.min(100, Math.round(value)));
  }

  function text(value, fallback) {
    if (value === null || value === undefined || value === '' || value === '-' || value === '?') {
      return fallback === undefined ? '—' : fallback;
    }
    if (Array.isArray(value)) {
      var joined = joinList(value);
      return joined || (fallback === undefined ? '—' : fallback);
    }
    if (typeof value === 'boolean') return value ? 'Yes' : 'No';
    return String(value);
  }

  function joinList(value, separator) {
    var list = Array.isArray(value)
      ? value
      : value === null || value === undefined || value === ''
        ? []
        : [value];
    return list
      .filter(function (item) { return item !== null && item !== undefined && String(item).trim() !== ''; })
      .map(function (item) { return String(item); })
      .join(separator || ', ');
  }

  function isOn(value) {
    if (value === true) return true;
    if (typeof value === 'number') return value > 0;
    if (typeof value === 'string') {
      var v = value.trim().toLowerCase();
      return /^(yes|true|on|1|connected|active|possible)\b/.test(v);
    }
    return false;
  }

  function isEnabled(value) {
    if (value === null || value === undefined || value === '') return false;
    if (typeof value === 'boolean') return value;
    if (typeof value === 'number') return value > 0;
    var v = String(value).trim().toLowerCase();
    return v !== 'none' && v !== 'no' && v !== 'off' && v !== 'false' && v !== '0' && v !== 'unknown' && v !== 'not connected' && v !== 'disabled';
  }

  function kindKey(kind) {
    var key = String(kind === null || kind === undefined ? '' : kind).toUpperCase();
    return KIND[key] ? key : '';
  }

  function kindLabel(kind) {
    var key = kindKey(kind);
    return key ? KIND_SHORT[key] : text(kind, 'Resolver');
  }

  function regionLabel(region) {
    var key = String(region === null || region === undefined ? '' : region).toUpperCase();
    return REGION[key] || text(region, 'Global');
  }

  function regionShort(region) {
    var key = String(region === null || region === undefined ? '' : region).toUpperCase();
    return {
      GL: 'Global',
      NA: 'N. America',
      SA: 'S. America',
      EU: 'Europe',
      AS: 'Asia',
      OC: 'Oceania',
      AF: 'Africa',
      LAN: 'LAN'
    }[key] || text(region, 'Global');
  }

  function latencyTone(value) {
    var ms = num(value);
    if (ms === null) return '';
    if (ms < 25) return 'good';
    if (ms < 60) return 'warn';
    return 'bad';
  }

  function scoreTone(value, best) {
    var score = num(value);
    if (score === null || score >= 99999) return '';
    var floor = num(best);
    if (floor === null) return latencyTone(score);
    var delta = score - floor;
    if (delta <= 5) return 'good';
    if (delta <= 20) return 'warn';
    return 'bad';
  }

  function toDate(value) {
    if (value === null || value === undefined || value === '') return null;
    var date = value instanceof Date ? value : new Date(value);
    return Number.isFinite(date.getTime()) ? date : null;
  }

  function timeAgo(value) {
    var date = toDate(value);
    if (!date) return '—';
    var diff = Date.now() - date.getTime();
    if (diff < 45 * 1000) return 'just now';
    var minutes = Math.floor(diff / 60000);
    if (minutes < 60) return Math.max(1, minutes) + 'm ago';
    var hours = Math.floor(minutes / 60);
    if (hours < 24) return hours + 'h ago';
    var label = date.getDate() + ' ' + MONTHS[date.getMonth()];
    if (date.getFullYear() !== new Date().getFullYear()) label += ' ' + date.getFullYear();
    return label;
  }

  function absoluteTime(value) {
    var date = toDate(value);
    if (!date) return '';
    var hh = String(date.getHours()).padStart(2, '0');
    var mm = String(date.getMinutes()).padStart(2, '0');
    return date.getDate() + ' ' + MONTHS[date.getMonth()] + ' ' + date.getFullYear() + ', ' + hh + ':' + mm;
  }

  function settingsOf(state) {
    return (state && state.settings) || {};
  }

  function resolversOf(state) {
    return Array.isArray(state && state.resolvers) ? state.resolvers : [];
  }

  function resultsOf(state) {
    return Array.isArray(state && state.results) ? state.results : [];
  }

  function historyOf(state) {
    return Array.isArray(state && state.history) ? state.history : [];
  }

  function bestRow(state) {
    var results = resultsOf(state);
    var best = state && state.best ? state.best : null;
    var bestScore = best ? num(best.score) : null;
    if (best && bestScore !== null && bestScore < 99999) {
      var full = results.find(function (row) {
        return row && (String(row.index) === String(best.index) || (best.name && row.name === best.name));
      });
      if (full) return full;
      return best;
    }
    var valid = results.filter(function (row) {
      var score = num(row && row.score);
      return score !== null && score < 99999;
    });
    if (!valid.length) return null;
    valid.sort(function (a, b) {
      return num(a.score) - num(b.score) || String(a.name || '').localeCompare(String(b.name || ''));
    });
    return valid[0];
  }

  function canWin(row) {
    var kind = kindKey(row && row.kind);
    return kind === 'U' || kind === 'C';
  }

  function leaderRow(state) {
    var rows = resultsOf(state).filter(function (row) {
      var score = num(row && row.score);
      return score !== null && score < 99999 && row.cached !== 'Timeout' && canWin(row);
    });
    if (!rows.length) return bestRow(state);
    rows.sort(function (a, b) {
      return num(a.score) - num(b.score) || String(a.name || '').localeCompare(String(b.name || ''));
    });
    return rows[0];
  }

  function isBaseline(row) {
    return Boolean(row) && kindKey(row.kind) === 'C';
  }

  function currentRow(state) {
    var results = resultsOf(state);
    var system = null;
    var baseline = null;
    for (var i = 0; i < results.length; i += 1) {
      var row = results[i];
      if (!row) continue;
      if (/current system dns/i.test(String(row.name || ''))) return row;
      if (kindKey(row.kind) === 'C') {
        if (/router|gateway/i.test(String(row.name || ''))) baseline = row;
        else if (!system) system = row;
      }
    }
    return system || baseline;
  }

  function lastRun(state) {
    var history = historyOf(state);
    if (history.length) return history[0];
    var results = resultsOf(state);
    if (!results.length) return null;
    var best = bestRow(state);
    return {
      at: state.startedAt,
      durationMs: state.durationMs,
      count: results.length,
      best: best ? best.name : null,
      score: best ? best.score : null
    };
  }

  function shortPath(value) {
    if (!value) return '';
    var match = String(value).match(/^\/Users\/[^/]+/);
    return match ? String(value).replace(match[0], '~') : String(value);
  }

  function asnLabel(value) {
    if (value === null || value === undefined || value === '') return '';
    var raw = String(value).trim();
    if (/^as/i.test(raw)) return raw.toUpperCase();
    return /^\d+$/.test(raw) ? 'AS' + raw : raw;
  }

  // -------------------------------------------------------------------------
  // small components
  // -------------------------------------------------------------------------
  function kindChip(kind) {
    var key = kindKey(kind);
    if (!key) return '';
    return '<span class="chip chip-' + key + '" title="' + esc(KIND[key]) + '">' + key + '</span>';
  }

  function flagChip(label, value) {
    var v = String(value === null || value === undefined ? '' : value).trim().toLowerCase();
    if (v === 'yes') {
      return '<span class="chip chip-good">' + icon('check', 11) + esc(label) + '</span>';
    }
    if (v === 'no') {
      return '<span class="chip">' + esc(label) + ' off</span>';
    }
    return '<span class="chip">' + esc(label) + ' ?</span>';
  }

  function nxChip(value) {
    var v = String(value === null || value === undefined ? '' : value).trim();
    if (v.toUpperCase() === 'HIJACK') {
      return '<span class="chip chip-bad">' + icon('alert', 11) + 'NX hijack</span>';
    }
    if (v.toLowerCase() === 'ok') {
      return '<span class="chip chip-good">' + icon('check', 11) + 'NX clean</span>';
    }
    return '<span class="chip">NX ?</span>';
  }

  function adsChip(value) {
    var v = String(value === null || value === undefined ? '' : value).trim().toLowerCase();
    if (v === 'yes') return '<span class="chip chip-A">Ads blocked</span>';
    if (v === 'no') return '<span class="chip">No ad block</span>';
    return '<span class="chip">Ads ?</span>';
  }

  function statusPill(state) {
    var status = (state && state.status) || 'idle';
    var progress = (state && state.progress) || {};
    var label = 'Ready';
    if (status === 'loading') label = 'Loading';
    else if (status === 'running') {
      label = progress.total ? 'Benchmarking · ' + (progress.done || 0) + '/' + progress.total : 'Benchmarking';
    } else if (status === 'done') label = 'Complete';
    else if (status === 'error') label = 'Needs attention';
    return '<span class="status-pill" data-state="' + esc(status) + '"><span class="status-dot"></span><span>' + esc(label) + '</span></span>';
  }

  function errorBanner(state) {
    if (!state || (!state.error && state.status !== 'error')) return '';
    var message = state.error || 'The benchmark did not finish.';
    return '<section class="card metric-bad fade-in" role="alert">' +
      '<div class="row">' +
        '<span class="chip chip-bad">' + icon('alert', 11) + 'Error</span>' +
        '<span class="spacer"></span>' +
        '<button class="btn btn-sm btn-ghost" type="button" data-action="run">' + icon('refresh', 13) + 'Try again</button>' +
      '</div>' +
      '<p class="card-subtitle">' + esc(message) + '</p>' +
    '</section>';
  }

  function emptyBlock(title, message, iconName, actions) {
    return '<div class="empty fade-in">' +
      '<div class="empty-icon">' + icon(iconName || 'sparkles', 30) + '</div>' +
      '<div class="empty-title">' + esc(title) + '</div>' +
      '<div class="empty-text">' + esc(message) + '</div>' +
      (actions || '') +
    '</div>';
  }

  function empty(title, message, iconName) {
    return emptyBlock(title, message, iconName, '');
  }

  function panel(title, subtitle, iconName, body, extra) {
    return '<section class="card fade-in">' +
      '<div class="card-header">' +
        '<div>' +
          '<div class="card-title">' + (iconName ? icon(iconName, 14) : '') + '<span>' + esc(title) + '</span></div>' +
          (subtitle ? '<div class="card-subtitle">' + esc(subtitle) + '</div>' : '') +
        '</div>' +
        (extra || '') +
      '</div>' +
      '<div class="card-body">' + body + '</div>' +
    '</section>';
  }

  function kvRow(label, value, right) {
    var shown = text(value);
    return '<div class="list-row">' +
      '<div>' +
        '<div class="list-row-title">' + esc(label) + '</div>' +
        '<div class="list-row-meta" title="' + esc(shown) + '">' + esc(shown) + '</div>' +
      '</div>' +
      (right || '') +
    '</div>';
  }

  function metricRow(label, value) {
    return '<div class="metric-row"><span>' + esc(label) + '</span><span class="value">' + esc(value) + '</span></div>';
  }

  function metricText(value, tone) {
    return '<span class="cell-num metric-value' + (tone ? ' metric-' + tone : '') + '">' + value + '</span>';
  }

  function latencyCell(value) {
    var ms = num(value);
    if (ms === null) return '<span class="muted">' + fmtMs(value) + '</span>';
    return metricText(fmtMs(ms), latencyTone(ms));
  }

  function serverList(servers, resolver) {
    var list = Array.isArray(servers) ? servers.filter(Boolean) : [];
    if (!list.length && resolver) {
      list = [].concat(resolver.v4 || [], resolver.v6 || []).filter(Boolean);
    }
    if (!list.length) return '<p class="muted">No server addresses reported.</p>';
    return '<div class="servers">' + list.map(function (address) {
      var value = String(address);
      return '<div class="server" title="' + esc(value) + '"><span>' + esc(value) + '</span><span>' + (value.indexOf(':') >= 0 ? 'IPv6' : 'IPv4') + '</span></div>';
    }).join('') + '</div>';
  }

  function sparkline(rows) {
    var values = (Array.isArray(rows) ? rows : [])
      .map(function (row) { return num(row && row.cached); })
      .filter(function (value) { return value !== null; })
      .slice(0, 16);
    if (values.length < 2) return '';
    var min = Math.min.apply(null, values);
    var max = Math.max.apply(null, values);
    var span = max - min || 1;
    var width = 72;
    var height = 18;
    var points = values.map(function (value, index) {
      var x = (index / (values.length - 1)) * width;
      var y = height - ((value - min) / span) * (height - 3) - 1.5;
      return x.toFixed(1) + ',' + y.toFixed(1);
    }).join(' ');
    return '<svg class="spark" viewBox="0 0 ' + width + ' ' + height + '" width="' + width + '" height="' + height + '" preserveAspectRatio="none" aria-hidden="true" focusable="false">' +
      '<polyline points="' + points + '" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round" opacity=".85"/>' +
    '</svg>';
  }

  function sortHeader(state, label, key, className) {
    var sort = (state && state.sort) || {};
    var active = sort.key === key;
    var ascending = sort.dir !== 'desc';
    return '<button class="' + className + '" type="button" data-action="sort" data-key="' + key + '"' +
      (active ? ' aria-sort="' + (ascending ? 'ascending' : 'descending') + '"' : '') +
      ' title="Sort by ' + esc(label) + '">' +
      esc(label) + (active ? icon('chevron', 10) : '') +
    '</button>';
  }

  // -------------------------------------------------------------------------
  // shell
  // -------------------------------------------------------------------------
  function sidebar(state) {
    var results = resultsOf(state);
    var resolvers = resolversOf(state);
    var history = historyOf(state);
    var active = (state && state.screen) || 'overview';
    var items = SCREENS.map(function (screen) {
      var badge = '';
      if (screen.key === 'benchmark') {
        var count = resolvers.length || results.length;
        if (count) badge = '<span class="nav-badge">' + count + '</span>';
      } else if (screen.key === 'history' && history.length) {
        badge = '<span class="nav-badge">' + Math.min(history.length, 20) + '</span>';
      }
      var isActive = active === screen.key;
      return '<button class="nav-item' + (isActive ? ' active' : '') + '" type="button" data-action="nav" data-screen="' + screen.key + '"' +
        (isActive ? ' aria-current="page"' : '') + ' aria-label="' + screen.label + '">' +
        '<span class="nav-icon">' + icon(screen.icon, 18) + '</span>' +
        '<span class="nav-label">' + screen.label + '</span>' +
        badge +
      '</button>';
    }).join('');

    return '<div class="sidebar-brand">' +
        '<div class="brand-mark">' + logo(30) + '</div>' +
        '<div class="brand-name">DNS Bench<span>macOS network tool</span></div>' +
      '</div>' +
      '<nav class="nav" aria-label="Screens">' + items + '</nav>' +
      '<div class="sidebar-footer">' +
        statusPill(state) +
        '<div class="sidebar-meta"><span>Version ' + esc((state && state.version) || '1.0.0') + '</span><span>⌘1 – ⌘5</span></div>' +
      '</div>';
  }

  function topbar(state) {
    var screen = (state && state.screen) || 'overview';
    var results = resultsOf(state);
    var network = state && state.network;
    var settings = settingsOf(state);
    var run = lastRun(state);
    var title = 'Overview';
    var subtitle = 'Your fastest DNS, at a glance';
    var action = '';

    if (screen === 'benchmark') {
      title = 'Benchmark';
      subtitle = resolversOf(state).length + ' resolvers · ' + text(settings.domain || 'google.com') + ' · ' +
        clampInt(settings.samples, 1, 20, 5) + ' samples';
    } else if (screen === 'network') {
      title = 'Network';
      subtitle = network
        ? [network.host, network.interface].filter(Boolean).join(' · ') || 'Connection, DNS and reachability'
        : 'Connection, DNS and reachability';
      action = '<button class="icon-btn" type="button" data-action="refresh-network" title="Refresh network information" aria-label="Refresh network information">' + icon('refresh', 16) + '</button>';
    } else if (screen === 'history') {
      title = 'History';
      subtitle = historyOf(state).length
        ? Math.min(historyOf(state).length, 20) + ' saved runs · kept on this Mac'
        : 'Every benchmark is saved here';
    } else if (screen === 'settings') {
      title = 'Settings';
      subtitle = 'Probe behaviour, exports and about';
      action = '<button class="icon-btn" type="button" data-action="open-results" title="Open results folder" aria-label="Open results folder">' + icon('external', 16) + '</button>';
    } else {
      title = 'Overview';
      subtitle = results.length
        ? results.length + ' resolvers probed · ' + timeAgo(run && run.at)
        : 'See how your DNS compares';
      action = state.status === 'running'
        ? '<button class="btn btn-sm btn-danger" type="button" data-action="cancel">' + icon('stop', 13) + 'Cancel</button>'
        : '<button class="btn btn-primary" type="button" data-action="run"' +
          (state.status === 'loading' || !resolversOf(state).length ? ' disabled' : '') + '>' + icon('play', 15) + 'Run benchmark</button>';
    }

    return '<div class="topbar-heading">' +
        '<div class="topbar-title">' + esc(title) + '</div>' +
        '<div class="topbar-subtitle">' + esc(subtitle) + '</div>' +
      '</div>' +
      '<div class="topbar-actions">' + statusPill(state) + action + '</div>';
  }

  // -------------------------------------------------------------------------
  // overview
  // -------------------------------------------------------------------------
  function metricGrid(state) {
    var best = bestRow(state);
    var network = state.network || null;
    var current = currentRow(state);
    var dnsInUse = network && Array.isArray(network.dnsInUse) ? network.dnsInUse : [];

    var currentTone = '';
    var currentValue = '—';
    var currentDelta = 'Run a benchmark to compare';
    if (current) {
      currentValue = fmtMs(current.cached);
      var currentScore = num(current.score);
      var leader = leaderRow(state);
      var bestScore = leader ? num(leader.score) : null;
      if (currentScore !== null && bestScore !== null) {
        var diff = Math.round(currentScore - bestScore);
        if (diff <= 0) {
          currentTone = 'good';
          currentDelta = 'Already the fastest';
        } else {
          currentTone = diff <= 5 ? 'good' : diff <= 40 ? 'warn' : 'bad';
          currentDelta = 'Score ' + Math.round(currentScore) + ' vs ' + Math.round(bestScore) +
            ' for ' + text(leader && leader.name, 'the fastest');
        }
      } else {
        currentDelta = 'In use right now';
      }
    } else if (dnsInUse.length) {
      currentValue = String(dnsInUse[0]);
      currentDelta = dnsInUse.length + (dnsInUse.length === 1 ? ' server' : ' servers') + ' · ' + text(network && network.dnsSource, 'In use');
    }

    var v6Known = network && network.v6 !== undefined && network.v6 !== null;
    var v6Available = v6Known ? isOn(network.v6) : resolversOf(state).some(function (resolver) {
      return resolver && Array.isArray(resolver.v6) && resolver.v6.filter(Boolean).length > 0;
    });
    var v6Answers = resultsOf(state).filter(function (row) { return num(row && row.v6dns) !== null; }).length;
    var v6Value = v6Available ? 'Available' : 'Unavailable';
    var v6Delta = v6Available
      ? v6Answers ? v6Answers + ' resolvers replied over IPv6' : 'IPv6 path detected'
      : 'Probing uses IPv4 only';

    var isp = network ? text(network.isp, '') : '';
    var networkValue = isp || text(network && network.host, 'This Mac');
    var networkParts = [];
    if (network) {
      var asn = asnLabel(network.asn);
      if (asn) networkParts.push(asn);
      var location = text(network.location, '');
      if (location) networkParts.push(location);
      if (!networkParts.length) {
        var publicIP = text(network.publicIP, '');
        if (publicIP) networkParts.push(publicIP);
      }
    }
    var networkDelta = networkParts.length ? networkParts.join(' · ') : 'No network details';

    return '<div class="metric-grid stagger">' +
      '<div class="metric' + (currentTone ? ' metric-' + currentTone : '') + '">' +
        '<div class="metric-label">Current DNS</div>' +
        '<div class="metric-value">' + esc(currentValue) + '</div>' +
        '<div class="metric-delta" title="' + esc(currentDelta) + '">' + esc(currentDelta) + '</div>' +
      '</div>' +
      '<div class="metric' + (v6Available ? ' metric-good' : ' metric-warn') + '">' +
        '<div class="metric-label">IPv6</div>' +
        '<div class="metric-value">' + esc(v6Value) + '</div>' +
        '<div class="metric-delta">' + esc(v6Delta) + '</div>' +
      '</div>' +
      '<div class="metric">' +
        '<div class="metric-label">Network</div>' +
        '<div class="metric-value" title="' + esc(networkValue) + '">' + esc(networkValue) + '</div>' +
        '<div class="metric-delta" title="' + esc(networkDelta) + '">' + esc(networkDelta) + '</div>' +
      '</div>' +
    '</div>';
  }

  function shortName(value) {
    var name = String(value === null || value === undefined ? '' : value).trim();
    if (!name) return 'fastest';
    return name.length > 22 ? name.slice(0, 21) + '…' : name;
  }

  function hero(state) {
    var leader = leaderRow(state);
    var best = bestRow(state);
    var score = leader ? num(leader.score) : null;
    var tone = latencyTone(score);
    var quality = score === null ? 0 : clampPct(100 - score);
    var current = currentRow(state);
    var settings = settingsOf(state);
    var samples = clampInt(settings.samples, 1, 20, 5);
    var comparison = '';
    var title = text(leader && leader.name, 'Your fastest resolver') + ' wins';
    var applyTarget = null;

    if (leader && isBaseline(leader)) {
      title = /router|gateway/i.test(String(leader.name || '')) ? 'Your router is the fastest' : 'Your current DNS is the fastest';
      var alternative = best && String(best.index) !== String(leader.index) ? best : null;
      if (alternative) {
        comparison = 'Best switchable resolver is <strong>' + esc(text(alternative.name, 'another resolver')) + '</strong> at ' +
          fmtMs(alternative.cached) + ' cached (score ' + fmtScore(alternative.score) + ').';
        applyTarget = alternative;
      } else {
        comparison = 'Nothing on this network beats it right now.';
      }
    } else if (leader) {
      applyTarget = leader;
      if (current && String(current.index) !== String(leader.index)) {
        var currentScore = num(current.score);
        if (currentScore !== null && score !== null) {
          var diff = Math.max(1, Math.round(currentScore - score));
          var currentLabel = /current system dns/i.test(String(current.name || ''))
            ? 'your current DNS'
            : esc(text(current.name, 'your current DNS'));
          comparison = 'That is <strong>' + diff + (diff === 1 ? ' point' : ' points') + '</strong> quicker than ' + currentLabel + '.';
        }
      } else {
        comparison = 'Your current DNS is already the fastest.';
      }
    } else {
      comparison = resultsOf(state).length + ' resolvers probed with ' + samples + ' samples each.';
    }

    var dnssec = leader && String(leader.dnssec).toLowerCase() === 'yes'
      ? '<span class="chip chip-good">' + icon('check', 11) + 'DNSSEC</span>'
      : '';
    var pop = leader && leader.pop && leader.pop !== '-' && leader.pop !== '?'
      ? '<span class="chip">' + esc(leader.pop) + '</span>'
      : '';
    var kindNote = leader && kindKey(leader.kind) === 'F'
      ? '<span class="chip chip-warn" title="This resolver filters or blocks some domains">Filtered</span>'
      : leader && kindKey(leader.kind) === 'A'
        ? '<span class="chip chip-warn" title="This resolver blocks ads and trackers">Blocks ads</span>'
        : '';

    var useButton = applyTarget && applyTarget.index !== undefined && applyTarget.index !== null
      ? '<button class="btn btn-ghost" type="button" data-action="apply" data-index="' + esc(applyTarget.index) + '">' +
        icon('bolt', 15) + 'Use ' + esc(shortName(applyTarget.name)) + '</button>'
      : '';

    return '<section class="hero fade-in">' +
      '<div class="hero-gauge' + (tone ? ' tone-' + tone : '') + '" style="--pct:' + quality + '" role="img" aria-label="Best score ' + esc(fmtScore(score)) + '">' +
        '<div class="gauge-ring"></div>' +
        '<div class="gauge-value">' + fmtScore(score) + '</div>' +
        '<div class="gauge-label">Best score</div>' +
      '</div>' +
      '<div class="hero-copy">' +
        '<h2>' + esc(title) + '</h2>' +
        '<p><strong>' + fmtMs(leader && leader.cached) + '</strong> cached · ' + fmtPct(leader && leader.loss) + ' loss · score <strong>' +
          fmtScore(score) + '</strong>. ' + comparison + '</p>' +
        '<div class="hero-actions">' +
          (state.status === 'running'
            ? '<button class="btn btn-danger" type="button" data-action="cancel">' + icon('stop', 15) + 'Cancel</button>'
            : '<button class="btn btn-primary" type="button" data-action="run">' + icon('play', 15) + 'Run benchmark</button>') +
          useButton + dnssec + kindNote + pop +
        '</div>' +
      '</div>' +
    '</section>';
  }

  function lastRunCard(state) {
    var run = lastRun(state);
    if (!run) return '';
    var when = timeAgo(run.at);
    var absolute = absoluteTime(run.at);
    var duration = run.durationMs ? fmtMs(run.durationMs) : '';
    var score = fmtScore(run.score);
    var count = num(run.count || (run.rows && run.rows.length)) || resultsOf(state).length;
    var whenLabel = when === '—' ? 'This session' : when;
    return '<section class="card fade-in">' +
      '<div class="card-header">' +
        '<div>' +
          '<div class="card-title">' + icon('clock', 14) + '<span>Last run</span></div>' +
          '<div class="card-subtitle">' + (run.best ? esc(run.best) + ' was fastest' : 'Most recent benchmark') +
            (absolute ? ' · ' + esc(absolute) : '') + '</div>' +
        '</div>' +
        '<div class="row wrap">' +
          '<span class="badge accent">' + esc(whenLabel) + '</span>' +
          (score !== '—' ? '<span class="badge good">' + score + '</span>' : '') +
          (duration ? '<span class="badge">' + esc(duration) + '</span>' : '') +
          '<span class="badge">' + count + ' resolvers</span>' +
        '</div>' +
      '</div>' +
    '</section>';
  }

  function topResolvers(state) {
    var rows = resultsOf(state).filter(function (row) {
      var score = num(row && row.score);
      return score !== null && score < 99999 && row.cached !== 'Timeout' && canWin(row);
    }).sort(function (a, b) {
      return num(a.score) - num(b.score) || String(a.name || '').localeCompare(String(b.name || ''));
    }).slice(0, 5);
    if (!rows.length) return '';

    var body = rows.map(function (row, index) {
      return '<button class="rank-row" type="button" data-action="open-resolver" data-index="' + esc(row.index) + '" title="Open in benchmark">' +
        '<span class="rank-num' + (index === 0 ? ' top' : '') + '">' + (index + 1) + '</span>' +
        '<span class="rank-main">' +
          '<span class="rank-name">' + kindChip(row.kind) + esc(text(row.name, 'Unknown resolver')) + '</span>' +
          '<span class="rank-meta">' + fmtMs(row.cached) + ' cached · ' + fmtPct(row.loss) + ' loss · score ' + fmtScore(row.score) + '</span>' +
        '</span>' +
        '<span class="rank-value" title="Score">' + fmtScore(row.score) + '</span>' +
        '<span class="rank-chevron">' + icon('chevron', 13) + '</span>' +
      '</button>';
    }).join('');

    return '<section class="card fade-in">' +
      '<div class="card-header">' +
        '<div>' +
          '<div class="card-title">' + icon('list', 14) + '<span>Top resolvers</span></div>' +
          '<div class="card-subtitle">Lowest scores from the last run · filtered resolvers are in the benchmark list</div>' +
        '</div>' +
        '<button class="btn btn-sm btn-ghost" type="button" data-action="nav" data-screen="benchmark">See all</button>' +
      '</div>' +
      '<div class="list">' + body + '</div>' +
    '</section>';
  }

  function overview(state) {
    var results = resultsOf(state);
    var missing = !state.network && !resolversOf(state).length;
    var running = state.status === 'running';
    var banner = errorBanner(state) + (running ? '<div class="fade-in">' + progress(state) + '</div>' : '');

    if (!results.length) {
      if (state.status === 'loading' || missing) {
        return banner +
          '<div class="empty fade-in">' +
            '<div class="empty-icon"><span class="spinner"></span></div>' +
            '<div class="empty-title">Preparing DNS Bench</div>' +
            '<div class="empty-text">Reading resolvers, network details and saved runs…</div>' +
          '</div>';
      }
      if (running) {
        return banner +
          emptyBlock(
            'Benchmark in progress',
            'Resolvers are being probed now. The fastest one will be highlighted here as soon as the first results land.',
            'activity',
            '<button class="btn btn-danger" type="button" data-action="cancel">' + icon('stop', 15) + 'Cancel benchmark</button>'
          ) +
          metricGrid(state) +
          lastRunCard(state);
      }
      var count = resolversOf(state).length;
      var actions = '<div class="hero-actions">' +
        '<button class="btn btn-primary" type="button" data-action="run"' + (count ? '' : ' disabled') + '>' + icon('play', 15) + 'Run benchmark</button>' +
        '<button class="btn btn-ghost" type="button" data-action="nav" data-screen="network">' + icon('globe', 15) + 'Inspect network</button>' +
      '</div>';
      return banner +
        emptyBlock(
          'Find your fastest DNS',
          'DNS Bench probes ' + (count ? count + ' resolvers' : 'public resolvers') +
            ' from this Mac — cached and cold lookups, jitter, loss, DNSSEC and ad blocking — then shows the winner.',
          'gauge',
          actions
        ) +
        metricGrid(state) +
        lastRunCard(state);
    }

    return banner + hero(state) + metricGrid(state) + lastRunCard(state) + topResolvers(state);
  }

  // -------------------------------------------------------------------------
  // benchmark
  // -------------------------------------------------------------------------
  function filteredRows(state) {
    var filter = (state && state.filter) || 'all';
    var query = String((state && state.search) || '').trim().toLowerCase();
    return resultsOf(state).filter(function (row) {
      if (!row) return false;
      if (filter !== 'all' && kindKey(row.kind) !== filter) return false;
      if (!query) return true;
      return [row.name, row.region, row.pop].some(function (value) {
        return String(value === null || value === undefined ? '' : value).toLowerCase().indexOf(query) >= 0;
      });
    });
  }

  function sortedRows(state) {
    var sort = (state && state.sort) || { key: 'score', dir: 'asc' };
    var key = sort.key || 'score';
    var direction = sort.dir === 'desc' ? -1 : 1;
    return filteredRows(state).slice().sort(function (a, b) {
      if (key === 'name') {
        var byName = String((a && a.name) || '').localeCompare(String((b && b.name) || ''), 'en', { sensitivity: 'base' });
        return byName * direction;
      }
      var av = num(a && a[key]);
      var bv = num(b && b[key]);
      if (key === 'score') {
        if (av !== null && av >= 99999) av = null;
        if (bv !== null && bv >= 99999) bv = null;
      }
      if (av === null && bv === null) return 0;
      if (av === null) return 1;
      if (bv === null) return -1;
      return (av - bv) * direction;
    });
  }

  function benchCount(state) {
    var all = resultsOf(state).length;
    var visible = filteredRows(state).length;
    var samples = clampInt(settingsOf(state).samples, 1, 20, 5);
    var progressData = (state && state.progress) || {};
    var parts;
    if (state && state.status === 'running' && Number(progressData.total) > 0) {
      parts = [
        (Number(progressData.done) || 0) + ' of ' + Number(progressData.total) + ' probed',
        samples + (samples === 1 ? ' sample' : ' samples')
      ];
    } else {
      parts = [
        visible === all ? all + ' resolvers' : visible + ' of ' + all + ' resolvers',
        samples + (samples === 1 ? ' sample' : ' samples')
      ];
    }
    return parts.join(' · ');
  }

  function progress(state) {
    var status = (state && state.status) || 'idle';
    var progressData = (state && state.progress) || {};
    var total = Math.max(0, Number(progressData.total) || resolversOf(state).length || 0);
    var done = Math.max(0, Number(progressData.done) || resultsOf(state).length || 0);
    var percent = total ? clampPct((done / total) * 100) : status === 'done' ? 100 : 0;
    var label = progressData.label;
    if (!label) {
      if (status === 'running') label = 'Probing resolvers…';
      else if (status === 'done') label = 'Complete';
      else if (status === 'error') label = 'Stopped';
      else if (status === 'loading') label = 'Loading…';
      else label = 'Ready to probe';
    }
    var meta;
    if (status === 'running') meta = total ? done + ' of ' + total : done + ' done';
    else if (status === 'done') meta = resultsOf(state).length + ' resolvers' + (state.durationMs ? ' · ' + fmtMs(state.durationMs) : '');
    else if (status === 'error') meta = 'Stopped';
    else meta = total ? total + ' resolvers' : '';
    var indicator = status === 'running'
      ? '<span class="spinner sm"></span>'
      : icon(status === 'done' ? 'check' : status === 'error' ? 'alert' : 'activity', 14);
    var fillTone = status === 'done' ? ' good' : status === 'error' ? ' bad' : '';

    return '<div class="progress" role="progressbar" aria-valuemin="0" aria-valuemax="100" aria-valuenow="' + percent +
      '" aria-label="Benchmark progress" data-state="' + esc(status) + '">' +
      '<div class="progress-label">' + indicator + '<span>' + esc(label) + '</span>' +
        (meta ? '<span class="progress-meta">' + esc(meta) + '</span>' : '') +
      '</div>' +
      '<div class="progress-track"><div class="progress-fill' + fillTone + '" style="width:' + percent + '%"></div></div>' +
    '</div>';
  }

  function benchRow(row, rank, maxCached, bestScore, state) {
    var selected = state && state.selected !== null && state.selected !== undefined &&
      String(state.selected) === String(row.index);
    var cached = num(row.cached);
    var width = cached === null || !maxCached ? 0 : Math.max(2, clampPct((cached / maxCached) * 100));
    var cachedTone = latencyTone(cached);
    var bar = '<div class="bar"><div class="bar-fill' + (cachedTone ? ' ' + cachedTone : '') + '" style="width:' + width + '%"></div></div>';
    var cachedCell = cached === null
      ? '<span class="muted">' + fmtMs(row.cached) + '</span>'
      : metricText(fmtMs(cached), cachedTone) + bar;
    var scoreValue = num(row.score);
    var scoreIsValid = scoreValue !== null && scoreValue < 99999;
    var lossValue = num(row.loss);
    var loss = lossValue !== null && lossValue > 0
      ? '<span class="badge bad">' + fmtPct(lossValue) + '</span>'
      : '<span class="muted">' + fmtPct(row.loss) + '</span>';
    var region = regionShort(row.region);
    var pop = row.pop && row.pop !== '-' && row.pop !== '?' ? String(row.pop) : '';
    var sub = pop || region;
    var fullSub = pop ? region + ' · ' + pop : region;
    var rowTitle = text(row.name, 'Unknown resolver') + ' · ' + fullSub;

    return '<div class="table-row' + (selected ? ' selected' : '') + '" data-action="select" data-index="' + esc(row.index) + '"' +
      ' role="button" tabindex="0" aria-pressed="' + (selected ? 'true' : 'false') + '" title="' + esc(rowTitle) + '">' +
      '<div class="cell cell-name">' +
        '<span class="badge' + (rank === 1 ? ' accent' : '') + '">' + rank + '</span>' +
        kindChip(row.kind) +
        '<span>' + esc(text(row.name, 'Unknown resolver')) + '</span>' +
        '<span class="cell-sub" title="' + esc(fullSub) + '">' + esc(sub) + '</span>' +
      '</div>' +
      '<div class="cell cell-num"><div>' + cachedCell + '</div></div>' +
      '<div class="cell cell-num">' + latencyCell(row.jitter) + '</div>' +
      '<div class="cell cell-num">' + loss + '</div>' +
      '<div class="cell cell-num">' + latencyCell(row.cold) + '</div>' +
      '<div class="cell cell-num">' + (scoreIsValid
        ? metricText(fmtScore(scoreValue), scoreTone(scoreValue, bestScore))
        : '<span class="muted">—</span>') + '</div>' +
      '<div class="cell cell-num">' + latencyCell(row.v4ping) + '</div>' +
    '</div>';
  }

  function benchTable(state) {
    var rows = sortedRows(state);
    var all = resultsOf(state);

    if (!rows.length) {
      if (!all.length) {
        if (state.status === 'running') {
          var total = (state.progress && state.progress.total) || resolversOf(state).length;
          return '<div class="empty">' +
            '<div class="empty-icon"><span class="spinner"></span></div>' +
            '<div class="empty-title">Probing ' + (total ? total + ' resolvers' : 'resolvers') + '</div>' +
            '<div class="empty-text">' + esc((state.progress && state.progress.label) || 'The first results appear in a few seconds.') + '</div>' +
          '</div>';
        }
        return emptyBlock(
          'No results yet',
          'Run a benchmark to probe ' + (resolversOf(state).length ? resolversOf(state).length + ' resolvers' : 'the public resolvers') + ' from this Mac.',
          'list',
          '<button class="btn btn-primary" type="button" data-action="run">' + icon('play', 15) + 'Run benchmark</button>'
        );
      }
      return emptyBlock(
        'No matching resolvers',
        'Nothing matches this filter and search. Try a different filter or clear the search field.',
        'search',
        '<button class="btn btn-ghost" type="button" data-action="filter" data-filter="all">' + icon('x', 13) + 'Show all</button>'
      );
    }

    var bestScore = null;
    all.forEach(function (row) {
      var score = num(row && row.score);
      if (score === null || score >= 99999) return;
      if (bestScore === null || score < bestScore) bestScore = score;
    });

    var maxCached = 1;
    rows.forEach(function (row) {
      var cached = num(row && row.cached);
      if (cached !== null && cached > maxCached) maxCached = cached;
    });

    var html = rows.map(function (row, index) {
      return benchRow(row, index + 1, maxCached, bestScore, state);
    }).join('');

    if (state.status === 'running') {
      var dashes = '<div class="cell cell-num muted">—</div>';
      html += '<div class="table-row shimmer" aria-hidden="true">' +
        '<div class="cell cell-name"><span class="spinner sm"></span><span class="muted">Probing remaining resolvers…</span></div>' +
        dashes + dashes + dashes + dashes + dashes + dashes +
      '</div>';
    }
    return html;
  }

  function benchmark(state) {
    var results = resultsOf(state);
    var running = state.status === 'running';
    var filters = FILTERS.map(function (filter) {
      var active = (state.filter || 'all') === filter.key;
      return '<button class="segmented-item' + (active ? ' active' : '') + '" type="button" data-action="filter" data-filter="' + filter.key + '"' +
        ' aria-pressed="' + (active ? 'true' : 'false') + '">' + filter.label + '</button>';
    }).join('');

    return errorBanner(state) +
      '<div class="row wrap fade-in">' +
        '<div class="segmented" role="group" aria-label="Filter resolvers">' + filters + '</div>' +
        '<label class="search">' + icon('search', 14) +
        '<input id="resolver-search" type="search" value="' + esc(state.search || '') + '" placeholder="Search resolvers" aria-label="Search resolvers" autocomplete="off" spellcheck="false">' +
        '</label>' +
        '<div id="bench-count" class="cell-sub">' + esc(benchCount(state)) + '</div>' +
        '<span class="spacer"></span>' +
        (running
          ? '<button class="btn btn-danger" type="button" data-action="cancel">' + icon('stop', 14) + 'Cancel</button>'
          : '<button class="btn btn-primary" type="button" data-action="run"' +
            (resolversOf(state).length ? '' : ' disabled') + '>' + icon('play', 15) + (results.length ? 'Run again' : 'Run benchmark') + '</button>') +
        '<button class="icon-btn" type="button" data-action="export" title="Export CSV" aria-label="Export CSV"' + (results.length ? '' : ' disabled') + '>' + icon('export', 16) + '</button>' +
      '</div>' +
      '<div id="bench-progress">' + progress(state) + '</div>' +
      '<div class="table fade-in">' +
        '<div class="table-head">' +
          sortHeader(state, 'Provider', 'name', 'cell') +
          sortHeader(state, 'Cached', 'cached', 'cell cell-num') +
          '<span class="cell cell-num">Jitter</span>' +
          sortHeader(state, 'Loss', 'loss', 'cell cell-num') +
          sortHeader(state, 'Cold', 'cold', 'cell cell-num') +
          sortHeader(state, 'Score', 'score', 'cell cell-num') +
          '<span class="cell cell-num">Ping</span>' +
        '</div>' +
        '<div id="bench-table">' + benchTable(state) + '</div>' +
      '</div>';
  }

  // -------------------------------------------------------------------------
  // network
  // -------------------------------------------------------------------------
  function sourceLabel(value) {
    var text_ = String(value === null || value === undefined ? '' : value).trim();
    if (!text_) return 'Unknown';
    if (/^manual\s*:/i.test(text_)) return 'Manual (set on this Mac)';
    if (/^automatic/i.test(text_)) return 'Automatic (DHCP / router)';
    if (/^\/etc\/resolv\.conf$/i.test(text_)) return 'From /etc/resolv.conf';
    return text_;
  }

  function network(state) {
    var net = state.network;
    if (!net) {
      return emptyBlock(
        'Network details unavailable',
        'Refresh to read the active interface, DNS servers, gateway and reachability checks.',
        'globe',
        '<button class="btn btn-primary" type="button" data-action="refresh-network">' + icon('refresh', 15) + 'Refresh network</button>'
      );
    }

    var v6On = isOn(net.v6);
    var vpnOn = isEnabled(net.vpn);
    var proxyOn = isEnabled(net.proxy);
    var interceptKnown = net.intercept !== null && net.intercept !== undefined;
    var captiveKnown = net.captive !== null && net.captive !== undefined;
    var interceptOn = isOn(net.intercept);
    var captiveOn = isOn(net.captive);
    var wifiText = typeof net.wifi === 'string' && net.wifi ? net.wifi : isOn(net.wifi) ? 'Wi-Fi' : '';
    var interfaceText = net.service
      ? net.service + (net.interface ? ' (' + net.interface + ')' : '')
      : text(net.interface, '—');
    var gatewayLoss = num(net.gatewayLoss);
    var gatewayRight = gatewayLoss !== null && gatewayLoss > 0
      ? '<span class="chip chip-bad">' + fmtPct(gatewayLoss) + ' loss</span>'
      : '<span class="chip chip-good">' + icon('check', 11) + 'OK</span>';
    var gatewayText = [text(net.gateway, 'Unknown'), net.gatewayMs !== null && net.gatewayMs !== undefined ? fmtMs(net.gatewayMs) : '']
      .filter(function (part) { return part && part !== '—'; }).join(' · ');

    var identity = panel(
      'This Mac',
      text(net.host, 'Local machine'),
      'cpu',
      kvRow('Host', net.host) +
      kvRow('System', [text(net.os, ''), text(net.arch, '')].filter(Boolean).join(' · ') || '—') +
      kvRow('Interface', interfaceText) +
      kvRow('Link', net.link || wifiText || '—') +
      kvRow('Wi-Fi network', wifiText || '—') +
      kvRow('Hardware address', net.mac) +
      kvRow('MTU', net.mtu ? net.mtu + ' bytes' : '—') +
      kvRow('Time zone', net.timezone)
    );

    var connection = panel(
      'Connection',
      net.service ? text(net.service) + ' · ' + text(net.interface) : 'Local and public addressing',
      'network',
      kvRow('Local IPv4', net.localIPv4) +
      kvRow('Local IPv6', joinList(net.localIPv6) || 'None') +
      kvRow('Gateway', gatewayText, gatewayRight) +
      kvRow('Public IPv4', net.publicIP) +
      kvRow('Public IPv6', net.publicIP6) +
      kvRow('ISP / ASN', [text(net.isp, ''), asnLabel(net.asn)].filter(Boolean).join(' · ') || '—') +
      kvRow('Location', text(net.location, '—')) +
      kvRow('VPN', vpnOn ? 'Connected' : 'Not connected', vpnOn ? '<span class="chip chip-warn">On</span>' : '<span class="chip">Off</span>') +
      kvRow('System proxy', proxyOn ? 'Configured' : 'None', proxyOn ? '<span class="chip chip-warn">On</span>' : '<span class="chip">Off</span>')
    );

    var dns = panel(
      'DNS',
      sourceLabel(net.dnsSource),
      'server',
      kvRow('Servers in use', joinList(net.dnsInUse) || 'Unknown', '<span class="badge accent">' +
        (Array.isArray(net.dnsInUse) ? net.dnsInUse.filter(Boolean).length : net.dnsInUse ? 1 : 0) + '</span>') +
      kvRow('Source', sourceLabel(net.dnsSource)) +
      kvRow('IPv6 resolution', v6On ? 'Working' : 'Unavailable', v6On ? '<span class="chip chip-good">' + icon('check', 11) + 'IPv6</span>' : '<span class="chip">IPv4</span>') +
      kvRow('Resolver egress', net.egress)
    );

    var health = panel(
      'Health checks',
      'Interception, captive portal and anycast location',
      'shield',
      kvRow(
        'DNS interception',
        !interceptKnown ? 'Not checked' : interceptOn ? 'Answers arriving from an unroutable address' : 'No port 53 rewrite detected',
        !interceptKnown
          ? '<span class="chip">Unknown</span>'
          : interceptOn ? '<span class="chip chip-bad">' + icon('alert', 11) + 'Detected</span>' : '<span class="chip chip-good">' + icon('check', 11) + 'Clear</span>'
      ) +
      kvRow(
        'Captive portal',
        !captiveKnown ? 'Not checked' : captiveOn ? 'HTTP probe did not reach the internet' : 'Internet reachable over HTTP',
        !captiveKnown
          ? '<span class="chip">Unknown</span>'
          : captiveOn ? '<span class="chip chip-warn">Possible</span>' : '<span class="chip chip-good">None</span>'
      ) +
      kvRow('Nearest PoP', net.pop || 'Unknown', isOn(net.warp) ? '<span class="chip chip-warn">WARP</span>' : '')
    );

    return '<div class="grid grid-2">' + identity + connection + '</div>' +
      '<div class="grid grid-2">' + dns + health + '</div>' +
      continentChart(net);
  }

  function continentChart(net) {
    var items = Array.isArray(net.continents) ? net.continents.filter(function (item) {
      return item && (item.city || item.region) && num(item.ms) !== null;
    }) : [];
    if (!items.length) return '';

    var sorted = items.slice().sort(function (a, b) { return num(a.ms) - num(b.ms); });
    var max = Math.max.apply(null, sorted.map(function (item) { return num(item.ms); }).concat(1));
    var closest = sorted[0];
    var rows = sorted.map(function (item) {
      var ms = num(item.ms);
      var tone = latencyTone(ms);
      var width = Math.max(3, clampPct((ms / max) * 100));
      var city = text(item.city, '');
      var region = regionLabel(item.region);
      var label = city || region;
      return '<div class="chart-row' + (tone ? ' ' + tone : '') + '">' +
        '<span class="chart-label" title="' + esc(region + (city ? ' · ' + city : '')) + '">' + esc(label) + '</span>' +
        '<div class="chart-track"><div class="chart-fill' + (tone ? ' ' + tone : '') + '" style="width:' + width + '%"></div></div>' +
        '<span class="chart-value">' + fmtMs(ms) + '</span>' +
      '</div>';
    }).join('');

    return panel(
      'Latency by continent',
      'TCP connect from this Mac to cloud regions',
      'globe',
      '<div class="chart">' + rows + '</div>',
      closest ? '<span class="badge accent">' + esc(text(closest.city, regionLabel(closest.region))) + '</span>' : ''
    );
  }

  // -------------------------------------------------------------------------
  // history
  // -------------------------------------------------------------------------
  function history(state) {
    var runs = historyOf(state).slice(0, 20);
    if (!runs.length) {
      return emptyBlock(
        'No runs yet',
        'Every benchmark is saved here — the last 20 runs, with the fastest resolver and full results.',
        'clock',
        '<button class="btn btn-primary" type="button" data-action="run">' + icon('play', 15) + 'Run benchmark</button>'
      );
    }

    var scores = runs.map(function (run) { return num(run && run.score); }).filter(function (score) {
      return score !== null && score < 99999;
    });
    var bestScore = scores.length ? Math.min.apply(null, scores) : null;

    var rows = runs.map(function (run) {
      var count = num(run.count || (run.rows && run.rows.length)) || 0;
      var tone = scoreTone(run.score, bestScore);
      var score = fmtScore(run.score);
      var duration = run.durationMs ? fmtMs(run.durationMs) : '';
      var meta = [timeAgo(run.at), count + ' resolvers'].concat(duration ? [duration] : []).join(' · ');
      var spark = sparkline(run.rows);
      return '<div class="list-row" title="' + esc(absoluteTime(run.at)) + '">' +
        '<div>' +
          '<div class="list-row-title">' + esc(text(run.best, 'Benchmark run')) + '</div>' +
          '<div class="list-row-meta">' + esc(meta) + '</div>' +
        '</div>' +
        spark +
        (score !== '—' ? '<span class="badge ' + (tone || 'accent') + '">' + score + '</span>' : '') +
        '<button class="btn btn-sm btn-ghost" type="button" data-action="load-run" data-id="' + esc(run.id === undefined ? '' : run.id) + '">' +
          icon('download', 13) + 'Load' +
        '</button>' +
      '</div>';
    }).join('');

    return '<section class="card fade-in">' +
      '<div class="card-header">' +
        '<div>' +
          '<div class="card-title">' + icon('clock', 14) + '<span>Recent runs</span></div>' +
          '<div class="card-subtitle">' + runs.length + ' saved · newest first · kept on this Mac</div>' +
        '</div>' +
        '<button class="btn btn-sm btn-ghost" type="button" data-action="run">' + icon('play', 13) + 'Run benchmark</button>' +
      '</div>' +
      '<div class="card-body"><div class="list">' + rows + '</div></div>' +
    '</section>';
  }

  // -------------------------------------------------------------------------
  // settings
  // -------------------------------------------------------------------------
  function settings(state) {
    var current = settingsOf(state);
    var samples = clampInt(current.samples, 1, 20, 5);
    var concurrency = clampInt(current.concurrency, 2, 32, 12);
    var domain = current.domain === null || current.domain === undefined ? 'google.com' : String(current.domain);
    var autoExport = current.autoExport !== false;
    var v6 = !!current.v6;

    var benchmark = panel(
      'Benchmark',
      'What every resolver is asked',
      'gauge',
      '<div class="field">' +
        '<label class="field-label" for="setting-samples"><span>Samples</span><span class="badge" data-setting-label="samples">' + samples + '</span></label>' +
        '<input id="setting-samples" class="slider" type="range" min="1" max="20" step="1" value="' + samples + '" data-setting="samples" aria-label="Samples per resolver">' +
        '<div class="field-hint">Lookups per resolver. More samples give steadier medians.</div>' +
      '</div>' +
      '<div class="field">' +
        '<label class="field-label" for="setting-domain"><span>Domain</span></label>' +
        '<input id="setting-domain" class="input" type="text" value="' + esc(domain) + '" data-setting="domain" placeholder="google.com" spellcheck="false" autocomplete="off">' +
        '<div class="field-hint">The name every resolver is asked to look up.</div>' +
      '</div>' +
      '<div class="field">' +
        '<label class="field-label" for="setting-concurrency"><span>Concurrency</span><span class="badge" data-setting-label="concurrency">' + concurrency + '</span></label>' +
        '<input id="setting-concurrency" class="slider" type="range" min="2" max="32" step="1" value="' + concurrency + '" data-setting="concurrency" aria-label="Resolvers probed at once">' +
        '<div class="field-hint">Resolvers probed at once. Higher finishes faster; lower is gentler.</div>' +
      '</div>'
    );

    var output = panel(
      'Output & network',
      'Exports, IPv6 and resolver state',
      'download',
      '<div class="field">' +
        '<label class="field-label" for="setting-auto-export"><span>Auto-export CSV</span>' +
          '<input id="setting-auto-export" class="switch" type="checkbox" data-setting="autoExport" aria-label="Auto-export CSV"' + (autoExport ? ' checked' : '') + '>' +
        '</label>' +
        '<div class="field-hint">Save results after every completed benchmark.</div>' +
      '</div>' +
      '<div class="field">' +
        '<label class="field-label" for="setting-v6"><span>Probe IPv6</span>' +
          '<input id="setting-v6" class="switch" type="checkbox" data-setting="v6" aria-label="Probe IPv6"' + (v6 ? ' checked' : '') + '>' +
        '</label>' +
        '<div class="field-hint">Use IPv6 resolvers when the network supports them.</div>' +
      '</div>' +
      '<div class="divider"></div>' +
      '<div class="list-row">' +
        '<div>' +
          '<div class="list-row-title">Results folder</div>' +
          '<div class="list-row-meta mono" title="' + esc(state.resultsDir || '') + '">' + esc(shortPath(state.resultsDir) || 'Default app folder') + '</div>' +
        '</div>' +
        '<button class="btn btn-sm btn-ghost" type="button" data-action="open-results">' + icon('external', 13) + 'Open</button>' +
      '</div>' +
      '<div class="list-row">' +
        '<div>' +
          '<div class="list-row-title">Reset DNS</div>' +
          '<div class="list-row-meta" title="Return macOS to the DNS servers handed out by DHCP.">Return macOS to the DNS servers handed out by DHCP.</div>' +
        '</div>' +
        '<button class="btn btn-sm btn-danger" type="button" data-action="reset">Reset</button>' +
      '</div>'
    );

    return '<div class="grid grid-2">' + benchmark + output + '</div>' + about(state);
  }

  function about(state) {
    var version = (state && state.version) || '1.0.0';
    return '<section class="card fade-in"><div class="about">' +
      '<div class="about-logo">' + logo(68) + '</div>' +
      '<h2>DNS Bench</h2>' +
      '<p>Measure the DNS resolvers this Mac can actually reach, inspect the path they take, and switch to the fastest with one click.</p>' +
      '<div class="about-links">' +
        '<a href="https://dharmsharma.com" target="_blank" rel="noreferrer noopener">' + icon('external', 12) + 'Dharm Sharma</a>' +
        '<a href="https://github.com/dharmsharma/dns-util" target="_blank" rel="noreferrer noopener">' + icon('external', 12) + 'Source &amp; CLI</a>' +
      '</div>' +
      '<p>Version ' + esc(version) + ' · MIT License · The same engine ships as <span class="mono">dns-bench.zsh</span> and <span class="mono">dns-bench.ps1</span>.</p>' +
    '</div></section>';
  }

  // -------------------------------------------------------------------------
  // inspector
  // -------------------------------------------------------------------------
  function inspector(state) {
    var selected = state && state.selected;
    if (selected === null || selected === undefined) {
      return emptyBlock(
        'Inspect a resolver',
        resultsOf(state).length
          ? 'Select any row in the benchmark table to see its probes, features and servers.'
          : 'Run a benchmark, then select a resolver to inspect it.',
        'list'
      );
    }

    var row = resultsOf(state).find(function (item) {
      return item && String(item.index) === String(selected);
    });
    var resolverForRow = resolversOf(state).find(function (item) {
      return item && String(item.index) === String(selected);
    });
    if (row) return inspectorResult(row, resolverForRow);

    var resolver = resolversOf(state).find(function (item) {
      return item && String(item.index) === String(selected);
    });
    if (resolver) return inspectorResolver(state, resolver);

    return emptyBlock('Resolver unavailable', 'Pick another row or run a fresh benchmark.', 'alert');
  }

  function inspectorResult(row, resolver) {
    var tone = latencyTone(row.cached);
    var score = num(row.score);
    var serverAddresses = Array.isArray(row.servers) ? row.servers : [];
    var features = [
      flagChip('DNSSEC', row.dnssec),
      nxChip(row.nx),
      flagChip('TCP', row.tcp),
      flagChip('DoT', row.dot),
      flagChip('443', row.doh),
      adsChip(row.ads)
    ].join('');
    var apply = kindKey(row.kind) === 'C'
      ? '<button class="btn btn-ghost" type="button" disabled>' + icon('check', 15) + 'In use</button>'
      : '<button class="btn btn-primary" type="button" data-action="apply" data-index="' + esc(row.index) + '">' + icon('bolt', 15) + 'Apply</button>';

    return '<div class="inspector-head">' +
        '<div>' +
          '<h2>' + esc(text(row.name, 'Resolver')) + '</h2>' +
          '<p>' + esc(regionLabel(row.region)) + ' · ' + esc(kindLabel(row.kind)) +
            (row.pop && row.pop !== '-' && row.pop !== '?' ? ' · ' + esc(row.pop) : '') + '</p>' +
        '</div>' +
        kindChip(row.kind) +
      '</div>' +
      '<div class="row wrap">' + features + '</div>' +
      '<div class="divider"></div>' +
      '<div class="metric">' +
        '<div class="metric-label">Cached median</div>' +
        '<div class="metric-value' + (tone ? ' metric-' + tone : '') + '">' + fmtMs(row.cached) + '</div>' +
        '<div class="metric-delta">Score ' + fmtScore(score !== null && score < 99999 ? score : row.score) + ' · ' + fmtPct(row.loss) + ' loss</div>' +
      '</div>' +
      '<div class="inspector-section">' +
        '<h3>Performance</h3>' +
        metricRow('Cold median', fmtMs(row.cold)) +
        metricRow('Jitter', fmtMs(row.jitter)) +
        metricRow('Packet loss', fmtPct(row.loss)) +
        metricRow('IPv4 ping', fmtMs(row.v4ping)) +
        metricRow('IPv6 DNS', fmtMs(row.v6dns)) +
        metricRow('IPv6 ping', fmtMs(row.v6ping)) +
        metricRow('Nearest PoP', text(row.pop)) +
      '</div>' +
      '<div class="inspector-section">' +
        '<h3>Servers</h3>' +
        serverList(serverAddresses, resolver) +
      '</div>' +
      '<div class="inspector-actions">' + apply + '</div>';
  }

  function inspectorResolver(state, resolver) {
    var running = state && state.status === 'running';
    var apply = kindKey(resolver.kind) === 'C'
      ? '<button class="btn btn-ghost" type="button" disabled>' + icon('check', 15) + 'In use</button>'
      : '<button class="btn btn-primary" type="button" data-action="apply" data-index="' + esc(resolver.index) + '">' + icon('bolt', 15) + 'Apply</button>';
    return '<div class="inspector-head">' +
        '<div>' +
          '<h2>' + esc(text(resolver.name, 'Resolver')) + '</h2>' +
          '<p>' + esc(regionLabel(resolver.region)) + ' · ' + esc(kindLabel(resolver.kind)) + '</p>' +
        '</div>' +
        kindChip(resolver.kind) +
      '</div>' +
      '<div class="row wrap">' +
        (running
          ? '<span class="chip chip-good"><span class="spinner sm"></span>Probing</span>'
          : '<span class="chip">Not probed yet</span>') +
      '</div>' +
      '<div class="divider"></div>' +
      '<p class="muted">' +
        (running
          ? 'Waiting for this resolver to finish its probes…'
          : 'Run a benchmark to collect latency, loss and diagnostics for this resolver.') +
      '</p>' +
      '<div class="inspector-section">' +
        '<h3>Servers</h3>' +
        serverList(null, resolver) +
      '</div>' +
      '<div class="inspector-actions">' + apply + '</div>';
  }

  // -------------------------------------------------------------------------
  // modal
  // -------------------------------------------------------------------------
  function confirm(state, opts) {
    opts = opts || {};
    var danger = !!opts.danger;
    var title = opts.title || 'Are you sure?';
    var message = opts.message || '';
    var label = opts.confirmLabel || 'Continue';
    var describedBy = message ? ' aria-describedby="confirm-message"' : '';
    return '<div class="modal-backdrop" role="presentation">' +
      '<div class="modal' + (danger ? ' metric-bad' : '') + '" role="alertdialog" aria-modal="true" aria-labelledby="confirm-title"' + describedBy + '>' +
        '<div class="modal-header">' +
          icon(danger ? 'alert' : 'info', 18) +
          '<div id="confirm-title">' + esc(title) + '</div>' +
          '<span class="spacer"></span>' +
          '<button class="icon-btn" type="button" data-action="close-modal" aria-label="Close" title="Close">' + icon('x', 14) + '</button>' +
        '</div>' +
        (message ? '<div class="modal-body" id="confirm-message"><p>' + esc(message) + '</p></div>' : '') +
        '<div class="modal-footer">' +
          '<button class="btn btn-ghost" type="button" data-action="confirm-cancel">Cancel</button>' +
          '<button class="btn ' + (danger ? 'btn-danger' : 'btn-primary') + '" type="button" data-action="confirm-ok">' + esc(label) + '</button>' +
        '</div>' +
      '</div>' +
    '</div>';
  }

  window.Views = {
    esc: esc,
    fmtMs: fmtMs,
    fmtScore: fmtScore,
    sidebar: sidebar,
    topbar: topbar,
    overview: overview,
    benchmark: benchmark,
    network: network,
    history: history,
    settings: settings,
    inspector: inspector,
    benchTable: benchTable,
    benchCount: benchCount,
    progress: progress,
    confirm: confirm,
    empty: empty
  };
})();

'use strict';

const api = window.dnsBench;

const DEFAULT_SETTINGS = {
  samples: 5,
  domain: 'google.com',
  concurrency: 12,
  autoExport: true,
  v6: false
};

const state = {
  screen: 'overview',
  status: 'loading',
  resolvers: [],
  results: [],
  network: null,
  history: [],
  progress: { done: 0, total: 0, label: '', phase: 'idle' },
  best: null,
  selected: null,
  filter: 'all',
  search: '',
  sort: { key: 'score', dir: 'asc' },
  settings: { ...DEFAULT_SETTINGS },
  error: null,
  startedAt: null,
  durationMs: null,
  version: '1.0.0',
  resultsDir: '',
  modal: null,
  pendingConfirm: null
};

const el = {
  app: document.getElementById('app'),
  sidebar: document.getElementById('sidebar'),
  topbar: document.getElementById('topbar'),
  content: document.getElementById('content'),
  inspector: document.getElementById('inspector'),
  toasts: document.getElementById('toasts'),
  modal: document.getElementById('modal-root')
};

let renderScheduled = false;

function scheduleRender() {
  if (renderScheduled) return;
  renderScheduled = true;
  window.requestAnimationFrame(() => {
    renderScheduled = false;
    render();
  });
}

function render() {
  const scrollTop = el.content.scrollTop;
  el.app.dataset.screen = state.screen;
  el.sidebar.innerHTML = window.Views.sidebar(state);
  el.topbar.innerHTML = window.Views.topbar(state);
  const screenView = window.Views[state.screen] || window.Views.overview;
  el.content.innerHTML = screenView(state);
  el.inspector.innerHTML = window.Views.inspector(state);
  el.modal.innerHTML = state.modal ? window.Views.confirm(state, state.modal) : '';
  el.content.scrollTop = scrollTop;
}

function updateTable() {
  const table = document.getElementById('bench-table');
  if (table && window.Views.benchTable) table.innerHTML = window.Views.benchTable(state);
  const count = document.getElementById('bench-count');
  if (count && window.Views.benchCount) count.innerHTML = window.Views.benchCount(state);
  const inspector = document.getElementById('inspector');
  if (inspector) inspector.innerHTML = window.Views.inspector(state);
}

function updateProgress() {
  const node = document.getElementById('bench-progress');
  if (node && window.Views.progress) node.innerHTML = window.Views.progress(state);
}

function toast(message, tone) {
  const node = document.createElement('div');
  node.className = `toast toast-${tone || 'info'}`;
  node.setAttribute('role', 'status');
  const icon = window.Icons.icon(tone === 'bad' ? 'alert' : tone === 'good' ? 'check' : 'info', 16);
  node.innerHTML = `${icon}<span></span>`;
  node.querySelector('span').textContent = message;
  el.toasts.appendChild(node);
  window.requestAnimationFrame(() => node.classList.add('show'));
  setTimeout(() => {
    node.classList.remove('show');
    setTimeout(() => node.remove(), 260);
  }, 4200);
}

function shortenPath(value) {
  if (!value) return '';
  const home = value.match(/^\/Users\/[^/]+/);
  return home ? value.replace(home[0], '~') : value;
}

function showConfirm(options, callback) {
  state.modal = options;
  state.pendingConfirm = callback;
  render();
}

function closeModal() {
  state.modal = null;
  state.pendingConfirm = null;
  render();
}

function setScreen(screen) {
  state.screen = screen;
  state.modal = null;
  render();
  el.content.focus({ preventScroll: true });
}

function updateSetting(key, value) {
  state.settings[key] = value;
  try {
    window.localStorage.setItem('dnsbench.settings', JSON.stringify(state.settings));
  } catch { /* ignore */ }
  api.saveSettings(state.settings);
  if (key === 'domain' || key === 'samples' || key === 'concurrency') {
    const label = document.querySelector(`[data-setting-label="${key}"]`);
    if (label) label.textContent = String(value);
  }
}

async function startBenchmark() {
  if (state.status === 'running') return;
  state.status = 'running';
  state.results = [];
  state.best = null;
  state.selected = null;
  state.error = null;
  state.startedAt = Date.now();
  state.durationMs = null;
  state.progress = {
    done: 0,
    total: state.resolvers.length,
    label: 'Preparing probes…',
    phase: 'prepare'
  };
  state.screen = 'benchmark';
  render();

  const response = await api.runBenchmark({
    samples: state.settings.samples,
    domain: state.settings.domain,
    concurrency: state.settings.concurrency,
    autoExport: state.settings.autoExport
  });

  if (response && response.ok === false) {
    state.status = 'error';
    state.error = response.message || 'Benchmark failed.';
    render();
  }
}

async function cancelBenchmark() {
  await api.cancelBenchmark();
  state.progress.label = 'Cancelling…';
  updateProgress();
}

async function applyResolver(index) {
  const resolver = state.resolvers.find((item) => item.index === index);
  const response = await api.applyResolver(index);
  if (response && response.ok) {
    if (response.status) {
      state.network = {
        ...(state.network || {}),
        dnsInUse: response.status.servers || [],
        dnsSource: response.status.mode || (state.network || {}).dnsSource
      };
    }
    toast(`Applied ${resolver ? resolver.name : 'resolver'}`, 'good');
    render();
  } else {
    toast((response && response.message) || 'Could not change DNS', 'bad');
  }
}

function resetDNS() {
  showConfirm({
    title: 'Reset DNS to automatic?',
    message: 'Your Mac will go back to the DNS servers handed out by your router (DHCP). The DNS cache is flushed afterwards.',
    confirmLabel: 'Reset DNS',
    danger: true
  }, async () => {
    const response = await api.resetDNS();
    if (response && response.ok) {
      state.network = {
        ...(state.network || {}),
        dnsInUse: (response.status && response.status.servers) || [],
        dnsSource: (response.status && response.status.mode) || 'automatic (DHCP/router)'
      };
      toast('DNS reset to automatic', 'good');
      render();
    } else {
      toast((response && response.message) || 'Reset failed', 'bad');
    }
  });
}

async function exportCSV() {
  const response = await api.exportCSV(state.results);
  if (response && response.ok) toast(`Exported to ${shortenPath(response.path)}`, 'good');
  else if (response && response.message) toast(response.message, 'bad');
}

async function refreshNetwork() {
  const init = await api.init();
  state.resolvers = init.resolvers || state.resolvers;
  state.network = init.network || state.network;
  state.history = init.history || state.history;
  state.resultsDir = init.resultsDir || state.resultsDir;
  toast('Network information refreshed', 'good');
  render();
}

function applyBest() {
  if (!state.best) {
    toast('Run a benchmark first', 'info');
    return;
  }
  applyResolver(state.best.index);
}

function handleAction(action, node) {
  switch (action) {
    case 'nav':
      setScreen(node.dataset.screen);
      break;
    case 'run':
      startBenchmark();
      break;
    case 'cancel':
      cancelBenchmark();
      break;
    case 'apply':
      applyResolver(Number(node.dataset.index));
      break;
    case 'reset':
      resetDNS();
      break;
    case 'export':
      exportCSV();
      break;
    case 'select':
      state.selected = Number(node.dataset.index);
      updateTable();
      break;
    case 'open-resolver':
      state.selected = Number(node.dataset.index);
      state.screen = 'benchmark';
      render();
      break;
    case 'filter':
      state.filter = node.dataset.filter;
      render();
      break;
    case 'sort': {
      const key = node.dataset.key;
      if (state.sort.key === key) {
        state.sort.dir = state.sort.dir === 'asc' ? 'desc' : 'asc';
      } else {
        state.sort = { key, dir: key === 'name' ? 'asc' : 'asc' };
      }
      updateTable();
      break;
    }
    case 'open-results':
      api.openResultsFolder();
      break;
    case 'settings':
      updateSetting(node.dataset.key, node.dataset.value === 'true' ? true : node.dataset.value === 'false' ? false : node.dataset.value);
      render();
      break;
    case 'refresh-network':
      refreshNetwork();
      break;
    case 'load-run': {
      const run = state.history.find((item) => String(item.id) === String(node.dataset.id));
      if (run) {
        state.results = run.rows || [];
        state.best = run.best ? { name: run.best, score: run.score, index: (run.rows || []).find((row) => row.name === run.best)?.index } : null;
        state.durationMs = run.durationMs || null;
        state.status = 'done';
        state.screen = 'benchmark';
        const leader = state.results
          .filter((row) => typeof row.score === 'number' && row.score < 99999 && row.cached !== 'Timeout')
          .sort((a, b) => a.score - b.score)[0];
        state.selected = leader ? leader.index : null;
        render();
      }
      break;
    }
    case 'close-modal':
    case 'confirm-cancel':
      closeModal();
      break;
    case 'confirm-ok': {
      const callback = state.pendingConfirm;
      state.modal = null;
      state.pendingConfirm = null;
      render();
      if (callback) callback();
      break;
    }
    default:
      break;
  }
}

document.addEventListener('click', (event) => {
  const node = event.target.closest('[data-action]');
  if (!node) return;
  event.preventDefault();
  handleAction(node.dataset.action, node);
});

document.addEventListener('input', (event) => {
  const input = event.target;
  if (input.id === 'resolver-search') {
    state.search = input.value;
    updateTable();
  }
  if (input.dataset && input.dataset.setting) {
    const key = input.dataset.setting;
    const value = input.type === 'range' || input.type === 'number' ? Number(input.value) : input.value;
    updateSetting(key, value);
  }
});

document.addEventListener('change', (event) => {
  const input = event.target;
  if (input.dataset && input.dataset.setting) {
    const key = input.dataset.setting;
    const value = input.type === 'checkbox' ? input.checked : input.type === 'range' || input.type === 'number' ? Number(input.value) : input.value;
    updateSetting(key, value);
  }
});

document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape' && state.modal) {
    closeModal();
    return;
  }
  if (!event.metaKey) return;
  const screens = ['overview', 'benchmark', 'network', 'history', 'settings'];
  const index = Number(event.key);
  if (index >= 1 && index <= screens.length) {
    event.preventDefault();
    setScreen(screens[index - 1]);
  }
});

// ---------------------------------------------------------------------------
// main-process events
// ---------------------------------------------------------------------------
api.onProgress((progress) => {
  state.progress = progress;
  if (state.screen === 'benchmark') updateProgress();
});

api.onResult((row) => {
  state.results.push(row);
  state.progress.done = state.results.length;
  if (state.screen === 'benchmark') {
    updateProgress();
    updateTable();
  }
});

api.onDone((payload) => {
  state.results = payload.rows || [];
  state.best = payload.best || null;
  state.durationMs = payload.durationMs || null;
  state.status = payload.cancelled ? 'idle' : 'done';
  state.progress = {
    done: state.results.length,
    total: state.results.length,
    label: payload.cancelled ? 'Cancelled' : 'Complete',
    phase: payload.cancelled ? 'cancelled' : 'done'
  };
  if (!payload.cancelled && state.results.length && state.selected === null) {
    const leader = state.results
      .filter((row) => typeof row.score === 'number' && row.score < 99999 && row.cached !== 'Timeout')
      .sort((a, b) => a.score - b.score)[0];
    if (leader) state.selected = leader.index;
  }
  if (payload.rows && payload.rows.length) {
    state.history = [{
      id: Date.now(),
      at: new Date().toISOString(),
      best: payload.best ? payload.best.name : null,
      score: payload.best ? payload.best.score : null,
      count: payload.rows.length,
      durationMs: payload.durationMs,
      rows: payload.rows
    }, ...state.history].slice(0, 20);
  }
  render();
  if (payload.csvPath) toast(`Results saved to ${shortenPath(payload.csvPath)}`, 'good');
});

api.onError((payload) => {
  state.status = 'error';
  state.error = payload.message;
  render();
  toast(payload.message || 'Benchmark failed', 'bad');
});

api.onCommand((command) => {
  if (command === 'run') startBenchmark();
  else if (command === 'cancel') cancelBenchmark();
  else if (command === 'apply-best') applyBest();
  else if (command === 'reset') resetDNS();
  else if (command === 'export') exportCSV();
});

api.onNavigate((screen) => setScreen(screen));

// ---------------------------------------------------------------------------
// boot
// ---------------------------------------------------------------------------
(async function boot() {
  try {
    const saved = window.localStorage.getItem('dnsbench.settings');
    if (saved) state.settings = { ...state.settings, ...JSON.parse(saved) };
  } catch { /* ignore */ }

  try {
    const init = await api.init();
    state.resolvers = init.resolvers || [];
    state.network = init.network || null;
    state.history = init.history || [];
    state.settings = { ...state.settings, ...(init.settings || {}) };
    state.version = init.version || state.version;
    state.resultsDir = init.resultsDir || '';
    state.status = 'idle';
    state.progress = { done: 0, total: state.resolvers.length, label: '', phase: 'idle' };
    if (state.history.length && state.history[0].rows && state.history[0].rows.length) {
      state.results = state.history[0].rows;
      state.best = state.history[0].best
        ? { name: state.history[0].best, score: state.history[0].score, index: (state.history[0].rows.find((row) => row.name === state.history[0].best) || {}).index }
        : null;
      state.durationMs = state.history[0].durationMs;
      state.status = 'done';
    }
    render();
  } catch (error) {
    state.status = 'error';
    state.error = error.message || String(error);
    render();
  }
})();

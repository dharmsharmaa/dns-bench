'use strict';

const { app, BrowserWindow, Menu, Tray, dialog, ipcMain, nativeImage, nativeTheme, shell } = require('electron');
const fs = require('fs');
const path = require('path');
const engine = require('./main/engine');

const APP_NAME = 'DNS Bench';
const USER_DATA = () => app.getPath('userData');
const RESULTS_DIR = () => path.join(USER_DATA(), 'results');
const HISTORY_FILE = () => path.join(USER_DATA(), 'history.json');
const SETTINGS_FILE = () => path.join(USER_DATA(), 'settings.json');
const WINDOW_FILE = () => path.join(USER_DATA(), 'window.json');

const argv = process.argv.slice(1);
const DEMO = argv.includes('--demo') || process.env.DNSBENCH_DEMO === '1';
const demo = DEMO ? require('./main/demo') : null;
const screenshotArg = argv.find((arg) => arg.startsWith('--screenshot='));
const screenshotPath = screenshotArg ? screenshotArg.split('=')[1] : null;
const screenshotRun = argv.includes('--screenshot-run');
const screenshotScreenArg = argv.find((arg) => arg.startsWith('--screenshot-screen='));
const screenshotScreen = screenshotScreenArg ? screenshotScreenArg.split('=')[1] : null;
const screenshotScrollArg = argv.find((arg) => arg.startsWith('--screenshot-scroll='));
const screenshotScroll = screenshotScrollArg ? Number(screenshotScrollArg.split('=')[1]) || 0 : 0;
const SCREENSHOT_SCREENS = ['overview', 'benchmark', 'network', 'history', 'settings'];
const delayArg = argv.find((arg) => arg.startsWith('--screenshot-delay='));
const screenshotDelay = delayArg ? Number(delayArg.split('=')[1]) || 1800 : 1800;

if (DEMO) console.log('[main] demo mode: no network access, no DNS changes');

app.setName(APP_NAME);
nativeTheme.themeSource = 'dark';

app.setAboutPanelOptions({
  applicationName: APP_NAME,
  applicationVersion: '1.0.0',
  version: '1.0.0',
  copyright: '© 2026 Dharm Sharma · MIT',
  credits: 'Benchmark, inspect and switch DNS resolvers.\nhttps://dharmsharma.com'
});

let mainWindow = null;
let tray = null;
let cachedResolvers = [];
let lastRows = [];
let lastBest = null;
let benchmarkRunning = false;
let cancelRequested = false;
let quitting = false;

// ---------------------------------------------------------------------------
// small file helpers
// ---------------------------------------------------------------------------
function readJSON(file, fallback) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    return fallback;
  }
}

function writeJSON(file, value) {
  try {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, JSON.stringify(value, null, 2));
    return true;
  } catch {
    return false;
  }
}

function timestamp() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}-${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
}

function csvCell(value) {
  const text = value === null || value === undefined ? '' : String(value);
  return /[",\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

function rowsToCSV(rows) {
  const header = [
    'sortkey', 'idx', 'name', 'kind', 'region', 'cached_ms', 'jitter_ms', 'loss_pct', 'cold_ms',
    'score', 'v4_ping', 'v6_dns', 'v6_ping', 'dnssec', 'nxdomain', 'tcp53', 'dot853', 'port443',
    'blocks_ads', 'pop'
  ];
  const lines = [header.join(',')];
  for (const row of rows) {
    lines.push([
      row.score, row.index, row.name, row.kind, row.region, row.cached, row.jitter, row.loss,
      row.cold, row.score, row.v4ping, row.v6dns, row.v6ping, row.dnssec, row.nx, row.tcp,
      row.dot, row.doh, row.ads, row.pop
    ].map(csvCell).join(','));
  }
  return lines.join('\n') + '\n';
}

function autoSaveCSV(rows) {
  try {
    fs.mkdirSync(RESULTS_DIR(), { recursive: true });
    const host = require('os').hostname().replace(/\.local$/, '');
    const file = path.join(RESULTS_DIR(), `dns-bench-${host}-${timestamp()}.csv`);
    fs.writeFileSync(file, rowsToCSV(rows));
    return file;
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// window
// ---------------------------------------------------------------------------
function defaultBounds() {
  return { width: 1440, height: 920 };
}

function savedBounds() {
  if (DEMO) return defaultBounds();
  const saved = readJSON(WINDOW_FILE(), null);
  if (!saved || !saved.width || !saved.height) return defaultBounds();
  return saved;
}

function createWindow() {
  const bounds = screenshotPath ? defaultBounds() : savedBounds();

  mainWindow = new BrowserWindow({
    ...bounds,
    minWidth: 1120,
    minHeight: 720,
    show: false,
    backgroundColor: '#0b0d12',
    titleBarStyle: 'hiddenInset',
    trafficLightPosition: { x: 18, y: 19 },
    vibrancy: 'under-window',
    visualEffectState: 'active',
    fullscreenable: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
      spellcheck: false
    }
  });

  mainWindow.webContents.on('console-message', (_event, level, message, line, sourceId) => {
    if (process.env.DNSBENCH_DEBUG) {
      console.log(`[renderer:${level}] ${message} (${sourceId}:${line})`);
    }
  });

  if (process.env.DNSBENCH_DEBUG) console.log('[main] loading renderer');

  mainWindow.loadFile(path.join(__dirname, 'renderer', 'index.html'));

  mainWindow.once('ready-to-show', () => {
    mainWindow.showInactive();
    if (!screenshotPath) {
      mainWindow.show();
      mainWindow.focus();
    }
  });

  mainWindow.on('close', (event) => {
    if (!quitting) {
      event.preventDefault();
      mainWindow.hide();
    }
  });

  mainWindow.on('resize', persistBounds);
  mainWindow.on('move', persistBounds);

  if (screenshotPath) {
    mainWindow.webContents.once('did-finish-load', async () => {
      if (screenshotScreen && SCREENSHOT_SCREENS.includes(screenshotScreen)) {
        for (let attempt = 0; attempt < 40; attempt++) {
          const ready = await mainWindow.webContents.executeJavaScript(
            `Boolean(document.querySelector('[data-action="nav"][data-screen="${screenshotScreen}"]'))`).catch(() => false);
          if (ready) {
            mainWindow.webContents.executeJavaScript(
              `document.querySelector('[data-action="nav"][data-screen="${screenshotScreen}"]').click()`).catch(() => {});
            break;
          }
          await new Promise((resolve) => setTimeout(resolve, 400));
        }
      }
      if (screenshotScroll > 0) {
        await mainWindow.webContents.executeJavaScript(
          `(() => { const el = document.getElementById('content'); if (el) el.scrollTop = ${screenshotScroll}; })()`).catch(() => {});
      }
      if (screenshotRun) {
        for (let attempt = 0; attempt < 40; attempt++) {
          const ready = await mainWindow.webContents.executeJavaScript(
            'Boolean(document.querySelector(\'[data-action="run"]\'))').catch(() => false);
          if (ready) {
            mainWindow.webContents.executeJavaScript(
              'document.querySelector(\'[data-action="run"]\').click()').catch(() => {});
            break;
          }
          await new Promise((resolve) => setTimeout(resolve, 400));
        }
      }
      setTimeout(async () => {
        try {
          const image = await mainWindow.webContents.capturePage();
          fs.writeFileSync(screenshotPath, image.toPNG());
          console.log(`screenshot: ${screenshotPath}`);
        } catch (error) {
          console.error('screenshot failed:', error.message);
        }
        quitting = true;
        app.quit();
      }, screenshotDelay);
    });
  }

  return mainWindow;
}

function persistBounds() {
  if (DEMO || !mainWindow || mainWindow.isDestroyed() || screenshotPath) return;
  const bounds = mainWindow.getBounds();
  writeJSON(WINDOW_FILE(), bounds);
}

function showWindow(screen) {
  if (!mainWindow) createWindow();
  if (mainWindow.isMinimized()) mainWindow.restore();
  mainWindow.show();
  mainWindow.focus();
  if (screen) mainWindow.webContents.send('app:navigate', screen);
}

// ---------------------------------------------------------------------------
// application menu
// ---------------------------------------------------------------------------
function buildMenu() {
  const send = (channel, payload) => {
    if (mainWindow && !mainWindow.isDestroyed()) mainWindow.webContents.send(channel, payload);
  };

  const template = [
    {
      label: APP_NAME,
      submenu: [
        { role: 'about' },
        { type: 'separator' },
        { label: 'Settings…', accelerator: 'CmdOrCtrl+,', click: () => showWindow('settings') },
        { type: 'separator' },
        { role: 'services' },
        { type: 'separator' },
        { role: 'hide' },
        { role: 'hideOthers' },
        { role: 'unhide' },
        { type: 'separator' },
        { role: 'quit' }
      ]
    },
    {
      label: 'Benchmark',
      submenu: [
        { label: 'Run Benchmark', accelerator: 'CmdOrCtrl+R', click: () => { showWindow('benchmark'); send('app:command', 'run'); } },
        { label: 'Cancel', accelerator: 'CmdOrCtrl+.', click: () => send('app:command', 'cancel') },
        { type: 'separator' },
        { label: 'Apply Best Resolver', click: () => send('app:command', 'apply-best') },
        { label: 'Reset DNS', click: () => send('app:command', 'reset') },
        { type: 'separator' },
        { label: 'Export CSV…', accelerator: 'CmdOrCtrl+E', click: () => send('app:command', 'export') }
      ]
    },
    {
      label: 'Edit',
      submenu: [
        { role: 'undo' }, { role: 'redo' }, { type: 'separator' },
        { role: 'cut' }, { role: 'copy' }, { role: 'paste' }, { role: 'selectAll' }
      ]
    },
    {
      label: 'View',
      submenu: [
        { role: 'reload' }, { role: 'forceReload' }, { role: 'toggleDevTools' },
        { type: 'separator' }, { role: 'resetZoom' }, { role: 'zoomIn' }, { role: 'zoomOut' },
        { type: 'separator' }, { role: 'togglefullscreen' }
      ]
    },
    {
      label: 'Window',
      submenu: [{ role: 'minimize' }, { role: 'zoom' }, { type: 'separator' }, { role: 'front' }]
    }
  ];

  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

// ---------------------------------------------------------------------------
// tray
// ---------------------------------------------------------------------------
function buildTray() {
  const iconPath = path.join(__dirname, 'resources', 'trayTemplate.png');
  let image = null;
  try {
    image = nativeImage.createFromPath(iconPath);
    if (!image.isEmpty()) image.setTemplateImage(true);
  } catch {
    image = null;
  }

  tray = new Tray(image && !image.isEmpty() ? image : nativeImage.createEmpty());
  if (!image || image.isEmpty()) tray.setTitle('DNS');
  tray.setToolTip('DNS Bench');

  const menu = Menu.buildFromTemplate([
    { label: 'Open DNS Bench', click: () => showWindow() },
    { type: 'separator' },
    { label: 'Run Benchmark', click: () => { showWindow('benchmark'); sendToRenderer('app:command', 'run'); } },
    {
      label: lastBest ? `Apply Best — ${lastBest.name}` : 'Apply Best Resolver',
      enabled: Boolean(lastBest),
      click: () => sendToRenderer('app:command', 'apply-best')
    },
    { label: 'Reset DNS', click: () => sendToRenderer('app:command', 'reset') },
    { type: 'separator' },
    { label: 'Open Results Folder', click: () => openResultsFolder() },
    { type: 'separator' },
    { label: 'Quit DNS Bench', click: () => { quitting = true; app.quit(); } }
  ]);

  tray.setContextMenu(menu);
  tray.on('click', () => showWindow());
}

function sendToRenderer(channel, payload) {
  if (mainWindow && !mainWindow.isDestroyed()) mainWindow.webContents.send(channel, payload);
}

async function openResultsFolder() {
  if (DEMO) return { ok: false, message: 'Demo mode.' };
  fs.mkdirSync(RESULTS_DIR(), { recursive: true });
  const error = await shell.openPath(RESULTS_DIR());
  return { ok: !error, message: error || undefined };
}

function refreshTrayMenu() {
  if (tray) {
    tray.destroy();
    tray = null;
  }
  buildTray();
}

// ---------------------------------------------------------------------------
// benchmark
// ---------------------------------------------------------------------------
async function ensureResolvers() {
  if (DEMO) return demo.resolvers;
  if (cachedResolvers.length) return cachedResolvers;
  const built = await engine.buildResolvers();
  cachedResolvers = built.resolvers;
  return cachedResolvers;
}

function pickBest(rows) {
  const candidates = rows
    .filter((row) => row.kind === 'U' && row.cached !== 'Timeout' && row.loss <= 20 && row.nx !== 'HIJACK')
    .sort((a, b) => Number(a.score) - Number(b.score));
  return candidates[0] || null;
}

async function handleDemoRun() {
  if (benchmarkRunning) return { ok: false, message: 'A benchmark is already running.' };
  benchmarkRunning = true;
  cancelRequested = false;

  const rows = demo.rows;
  const total = rows.length;
  sendToRenderer('benchmark:progress', { done: 0, total, label: 'Preparing probes…', phase: 'prepare' });

  try {
    for (let index = 0; index < total; index++) {
      await new Promise((resolve) => setTimeout(resolve, 50));
      if (cancelRequested || !benchmarkRunning) {
        sendToRenderer('benchmark:done', { rows: rows.slice(0, index), best: null, durationMs: 0, cancelled: true, csvPath: null });
        return { ok: true, cancelled: true };
      }
      sendToRenderer('benchmark:result', rows[index]);
      sendToRenderer('benchmark:progress', {
        done: index + 1,
        total,
        label: rows[index].name,
        phase: 'probe'
      });
    }

    const best = pickBest(rows);
    lastRows = rows;
    lastBest = best;
    refreshTrayMenu();
    sendToRenderer('benchmark:done', { rows, best, durationMs: 21400, csvPath: null });
    return { ok: true };
  } finally {
    benchmarkRunning = false;
  }
}

async function handleRun(options) {
  if (DEMO) return handleDemoRun();
  if (process.env.DNSBENCH_DEBUG) console.log('[main] benchmark:run requested', JSON.stringify(options || {}));
  if (benchmarkRunning) return { ok: false, message: 'A benchmark is already running.' };
  benchmarkRunning = true;
  cancelRequested = false;

  const settings = { ...readJSON(SETTINGS_FILE(), {}), ...(options || {}) };
  const samples = Math.min(20, Math.max(1, Number(settings.samples) || 5));
  const concurrency = Math.min(32, Math.max(2, Number(settings.concurrency) || 12));
  const domain = String(settings.domain || 'google.com');

  try {
    const resolvers = await ensureResolvers();
    const rows = [];
    const startedAt = Date.now();

    const results = await engine.runBenchmark({
      resolvers,
      samples,
      domain,
      concurrency,
      isCancelled: () => !benchmarkRunning,
      onProgress: (progress) => sendToRenderer('benchmark:progress', progress),
      onResult: (row) => {
        rows.push(row);
        sendToRenderer('benchmark:result', row);
      }
    });

    const durationMs = Date.now() - startedAt;
    const finalRows = results || rows;
    const best = pickBest(finalRows);
    lastRows = finalRows;
    lastBest = best;

    let csvPath = null;
    if (settings.autoExport !== false && finalRows.length) {
      csvPath = autoSaveCSV(finalRows);
    }

    if (finalRows.length) {
      const history = readJSON(HISTORY_FILE(), []);
      history.unshift({
        id: Date.now(),
        at: new Date().toISOString(),
        best: best ? best.name : null,
        score: best ? best.score : null,
        count: finalRows.length,
        durationMs,
        rows: finalRows
      });
      writeJSON(HISTORY_FILE(), history.slice(0, 20));
    }

    refreshTrayMenu();
    sendToRenderer('benchmark:done', { rows: finalRows, best, durationMs, csvPath, cancelled: cancelRequested });
    return { ok: true, csvPath, cancelled: cancelRequested };
  } catch (error) {
    sendToRenderer('benchmark:error', { message: error.message });
    return { ok: false, message: error.message };
  } finally {
    benchmarkRunning = false;
  }
}

// ---------------------------------------------------------------------------
// IPC
// ---------------------------------------------------------------------------
ipcMain.handle('app:init', async () => {
  if (DEMO) {
    cachedResolvers = demo.resolvers;
    return {
      resolvers: demo.resolvers,
      network: demo.network,
      history: demo.history,
      settings: demo.settings,
      version: app.getVersion(),
      resultsDir: ''
    };
  }
  const built = await engine.buildResolvers();
  cachedResolvers = built.resolvers;
  return {
    resolvers: built.resolvers,
    network: built.network,
    history: readJSON(HISTORY_FILE(), []),
    settings: readJSON(SETTINGS_FILE(), {}),
    version: app.getVersion(),
    resultsDir: RESULTS_DIR()
  };
});

ipcMain.handle('benchmark:run', async (_event, options) => handleRun(options));

ipcMain.handle('benchmark:cancel', async () => {
  cancelRequested = true;
  benchmarkRunning = false;
  if (!DEMO) engine.cancel();
  return { ok: true };
});

ipcMain.handle('dns:apply', async (_event, index) => {
  if (DEMO) return { ok: false, message: 'Demo mode: DNS is not changed.' };
  const resolvers = await ensureResolvers();
  const resolver = resolvers.find((item) => item.index === Number(index));
  if (!resolver) return { ok: false, message: 'Unknown resolver.' };
  try {
    const result = await engine.applyResolver(resolver, { hasV6: Boolean(readJSON(SETTINGS_FILE(), {}).v6) });
    const status = await engine.getDnsStatus();
    return { ...result, status };
  } catch (error) {
    return { ok: false, message: error.message };
  }
});

ipcMain.handle('dns:reset', async () => {
  if (DEMO) return { ok: false, message: 'Demo mode: DNS is not changed.' };
  try {
    const result = await engine.resetDNS();
    const status = await engine.getDnsStatus();
    return { ...result, status };
  } catch (error) {
    return { ok: false, message: error.message };
  }
});

ipcMain.handle('dns:status', async () => {
  if (DEMO) return { mode: demo.network.dnsSource, servers: demo.network.dnsInUse, service: demo.network.service };
  return engine.getDnsStatus();
});

ipcMain.handle('csv:export', async (_event, rows) => {
  if (DEMO) return { ok: false, message: 'Demo mode: nothing exported.' };
  const exportRows = Array.isArray(rows) && rows.length ? rows : lastRows;
  if (!exportRows.length) return { ok: false, message: 'Nothing to export yet.' };
  const result = await dialog.showSaveDialog(mainWindow, {
    title: 'Export DNS Benchmark',
    defaultPath: path.join(app.getPath('downloads'), `dns-bench-${timestamp()}.csv`),
    filters: [{ name: 'CSV', extensions: ['csv'] }]
  });
  if (result.canceled || !result.filePath) return { ok: false, cancelled: true };
  try {
    fs.writeFileSync(result.filePath, rowsToCSV(exportRows));
    return { ok: true, path: result.filePath };
  } catch (error) {
    return { ok: false, message: error.message };
  }
});

ipcMain.handle('results:open', async () => {
  if (DEMO) return { ok: false, message: 'Demo mode.' };
  return openResultsFolder();
});

ipcMain.handle('settings:save', async (_event, settings) => {
  if (DEMO) return { ok: true };
  writeJSON(SETTINGS_FILE(), settings || {});
  return { ok: true };
});

// ---------------------------------------------------------------------------
// lifecycle
// ---------------------------------------------------------------------------
const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
} else {
  app.on('second-instance', () => showWindow());

  app.whenReady().then(() => {
    buildMenu();
    createWindow();
    buildTray();

    app.on('activate', () => showWindow());
  });

  app.on('before-quit', () => {
    quitting = true;
    if (!DEMO) engine.cancel();
  });

  app.on('window-all-closed', () => {
    if (process.platform !== 'darwin') app.quit();
  });
}

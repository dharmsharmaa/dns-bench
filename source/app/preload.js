'use strict';

const { contextBridge, ipcRenderer } = require('electron');

function on(channel, callback) {
  const listener = (_event, payload) => callback(payload);
  ipcRenderer.on(channel, listener);
  return () => ipcRenderer.removeListener(channel, listener);
}

contextBridge.exposeInMainWorld('dnsBench', {
  init: () => ipcRenderer.invoke('app:init'),
  runBenchmark: (options) => ipcRenderer.invoke('benchmark:run', options),
  cancelBenchmark: () => ipcRenderer.invoke('benchmark:cancel'),
  applyResolver: (index) => ipcRenderer.invoke('dns:apply', index),
  resetDNS: () => ipcRenderer.invoke('dns:reset'),
  dnsStatus: () => ipcRenderer.invoke('dns:status'),
  exportCSV: (rows) => ipcRenderer.invoke('csv:export', rows),
  openResultsFolder: () => ipcRenderer.invoke('results:open'),
  saveSettings: (settings) => ipcRenderer.invoke('settings:save', settings),
  onProgress: (callback) => on('benchmark:progress', callback),
  onResult: (callback) => on('benchmark:result', callback),
  onDone: (callback) => on('benchmark:done', callback),
  onError: (callback) => on('benchmark:error', callback),
  onCommand: (callback) => on('app:command', callback),
  onNavigate: (callback) => on('app:navigate', callback)
});

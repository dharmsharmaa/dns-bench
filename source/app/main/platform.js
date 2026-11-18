'use strict';

const { execFile } = require('child_process');
const fs = require('fs');
const net = require('net');
const path = require('path');

const MAX_BUFFER = 4 * 1024 * 1024;
const DEFAULT_TIMEOUT = 8000;
const ADMIN_TIMEOUT = 120000; // long enough for the macOS password prompt

function run(cmd, args = [], opts = {}) {
  return new Promise((resolve) => {
    const argv = Array.isArray(args) ? args.map(String) : [String(args)];
    const options = {
      timeout: Number(opts.timeout) > 0 ? Number(opts.timeout) : DEFAULT_TIMEOUT,
      maxBuffer: opts.maxBuffer || MAX_BUFFER,
      encoding: 'utf8',
      killSignal: 'SIGKILL'
    };
    if (opts.cwd) options.cwd = opts.cwd;
    if (opts.env) options.env = opts.env;

    try {
      execFile(String(cmd), argv, options, (error, stdout, stderr) => {
        const out = typeof stdout === 'string' ? stdout : '';
        const err = typeof stderr === 'string' ? stderr : '';
        if (!error) {
          resolve({ stdout: out, stderr: err, code: 0 });
          return;
        }
        const code = typeof error.code === 'number' ? error.code : (error.killed ? 124 : 127);
        resolve({ stdout: out, stderr: err || error.message || 'command failed', code });
      });
    } catch (error) {
      resolve({ stdout: '', stderr: error.message || String(error), code: 1 });
    }
  });
}

function shell(command, opts = {}) {
  return run('/bin/zsh', ['-lc', String(command)], {
    timeout: opts.timeout || DEFAULT_TIMEOUT,
    maxBuffer: opts.maxBuffer
  });
}

function adminShell(command, opts = {}) {
  const escaped = String(command).replace(/\\/g, '\\\\').replace(/"/g, '\\"');
  const script = `do shell script "${escaped}" with administrator privileges`;
  return run('/usr/bin/osascript', ['-e', script], { timeout: opts.timeout || ADMIN_TIMEOUT }).then((result) => {
    if (result.code !== 0 && /cancel/i.test(result.stderr) && !/User canceled/i.test(result.stderr)) {
      return { ...result, stderr: `User canceled. ${result.stderr}`.trim() };
    }
    return result;
  });
}

function tcpConnect(host, port, timeoutMs = 3000) {
  return new Promise((resolve) => {
    let settled = false;
    let socket = null;
    const started = process.hrtime.bigint();

    const finish = (value) => {
      if (settled) return;
      settled = true;
      if (socket) {
        try {
          socket.destroy();
        } catch {
          /* socket already gone */
        }
      }
      resolve(value);
    };

    try {
      socket = new net.Socket();
      socket.setTimeout(Math.max(250, Number(timeoutMs) || 3000));
      socket.once('connect', () => {
        const elapsed = Number(process.hrtime.bigint() - started) / 1e6;
        finish(Math.max(1, Math.round(elapsed)));
      });
      socket.once('timeout', () => finish(null));
      socket.once('error', () => finish(null));
      socket.once('close', () => finish(null));
      socket.connect(Number(port), String(host));
    } catch {
      finish(null);
    }
  });
}

function isExecutable(file) {
  try {
    if (!fs.statSync(file).isFile()) return false;
    fs.accessSync(file, fs.constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

function which(cmd) {
  try {
    const name = String(cmd || '').trim();
    if (!name) return false;
    if (name.includes('/')) return isExecutable(name);
    const dirs = (process.env.PATH || '').split(path.delimiter).filter(Boolean);
    dirs.push('/usr/bin', '/usr/sbin', '/bin', '/sbin', '/usr/local/bin', '/opt/homebrew/bin');
    return dirs.some((dir) => isExecutable(path.join(dir, name)));
  } catch {
    return false;
  }
}

module.exports = { run, shell, adminShell, tcpConnect, which };

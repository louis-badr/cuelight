// Cuelight VS Code extension.
// 1. Colors the title bar with a color derived from the project name.
// 2. Writes ~/.cuelight/windows/<id>.json while the window is open.
// 3. Starts the Cuelight menu bar app if it isn't running.
const vscode = require('vscode');
const { execFile } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');

// Must stay identical to PALETTES in menubar-app/main.swift (see docs/color.md).
const PALETTES = {
  vivid: ['#2D5BE3', '#13915F', '#D03A3A', '#7B3FE4', '#0E8AA0', '#C93782', '#DD6B20', '#5E9E1E'],
  soft: ['#4E6FAE', '#4E8B6B', '#B5524F', '#7D62AE', '#3F8C99', '#A85A85', '#C07A3E', '#7F8C3F'],
  pastel: ['#9DBDF2', '#97D8B2', '#F2A6A0', '#C6B0F2', '#93D3DD', '#F0ABCD', '#F6C28E', '#D2DE92'],
};
const STATE_DIR = path.join(os.homedir(), '.cuelight');
const TITLE_KEYS = ['titleBar.activeBackground', 'titleBar.activeForeground', 'titleBar.inactiveBackground', 'titleBar.inactiveForeground'];

const SETTINGS_FILE = path.join(STATE_DIR, 'settings.json');

let windowFile = null;
let windowRecord = null;
let projectName = null;

function readJSON(file) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return {}; }
}

function colorFor(name) {
  const overrides = readJSON(path.join(STATE_DIR, 'colors.json'));
  if (overrides[name]) return overrides[name];
  const palette = PALETTES[readJSON(SETTINGS_FILE).palette] || PALETTES.pastel;
  const hash = crypto.createHash('sha256').update(name, 'utf8').digest();
  return palette[hash.readUInt32BE(0) % palette.length];
}

// Dark text on light colors (WCAG relative luminance > 0.4), white otherwise.
function textColorFor(hex) {
  const [r, g, b] = [1, 3, 5].map(i => {
    const c = parseInt(hex.slice(i, i + 2), 16) / 255;
    return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.4 ? '#1D1D22' : '#FFFFFF';
}

function writeAtomic(file, text) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const tmp = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, text);
  fs.renameSync(tmp, file);
}

async function colorTitleBar(color) {
  const config = vscode.workspace.getConfiguration('workbench');
  const current = config.inspect('colorCustomizations').workspaceValue || {};
  const text = textColorFor(color);
  const wanted = {
    'titleBar.activeBackground': color,
    'titleBar.activeForeground': text,
    'titleBar.inactiveBackground': color + 'B3',
    'titleBar.inactiveForeground': text + '99',
  };
  if (TITLE_KEYS.every(k => current[k] === wanted[k])) return; // already set: don't touch the file
  await config.update('colorCustomizations', { ...current, ...wanted }, vscode.ConfigurationTarget.Workspace);
}

function registerWindow(folderPath, name) {
  const id = crypto.createHash('sha1').update(folderPath).digest('hex').slice(0, 12);
  windowFile = path.join(STATE_DIR, 'windows', `${id}.json`);
  windowRecord = { path: folderPath, name, pid: process.pid, openedAt: new Date().toISOString() };
  writeFocus(vscode.window.state.focused);
}

// Rewrites the window file with the focus state. lastFocusedAt is updated when the window gains
// and when it loses the focus, so the app knows whether a finished Claude turn was seen.
function writeFocus(focused) {
  if (!windowFile) return;
  const wasFocused = windowRecord.focused;
  windowRecord.focused = focused;
  if (focused || wasFocused) windowRecord.lastFocusedAt = new Date().toISOString();
  writeAtomic(windowFile, JSON.stringify(windowRecord, null, 2));
}

function unregisterWindow() {
  if (windowFile) { try { fs.unlinkSync(windowFile); } catch {} }
  windowFile = null;
  windowRecord = null;
}

async function setup() {
  unregisterWindow();
  const folder = vscode.workspace.workspaceFolders && vscode.workspace.workspaceFolders[0];
  if (!folder || folder.uri.scheme !== 'file') return;
  const folderPath = folder.uri.fsPath.replace(/\/+$/, '');
  const name = path.basename(folderPath);
  projectName = name;
  registerWindow(folderPath, name);
  // -g: stay in the background. Does nothing visible if the app is already running.
  execFile('/usr/bin/open', ['-g', '-b', 'com.louisbadr.cuelight'], () => {});
  await colorTitleBar(colorFor(name));
}

function activate(context) {
  setup().catch(err => console.error('Cuelight:', err));
  context.subscriptions.push(vscode.workspace.onDidChangeWorkspaceFolders(() => setup()));
  context.subscriptions.push(vscode.window.onDidChangeWindowState(state => {
    if (windowRecord && state.focused !== windowRecord.focused) writeFocus(state.focused);
  }));
  // Palette changed from the app's menu. watchFile polls the path, so it survives atomic renames.
  const onSettings = () => { if (projectName) colorTitleBar(colorFor(projectName)).catch(() => {}); };
  fs.watchFile(SETTINGS_FILE, { interval: 1000 }, onSettings);
  context.subscriptions.push({ dispose: () => fs.unwatchFile(SETTINGS_FILE, onSettings) });
}

function deactivate() {
  unregisterWindow();
}

module.exports = { activate, deactivate };

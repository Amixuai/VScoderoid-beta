// Writes node_modules/.vscodroid-bins for the project at argv[2].
//
// Why this exists: on Android a project in shared storage cannot hold the
// symbolic links npm normally makes in node_modules/.bin, so the command
// wrapper installs with --no-bin-links. Package commands (vite, tsc, eslint...)
// are then found through this list instead: one "name relative/path.js" line per
// command, read by command-wrapper.sh, which turns each into a shell function.
//
// Plain files only. Nothing here creates a link.
'use strict';
const fs = require('fs');
const path = require('path');

const root = path.resolve(process.argv[2] || '.');
const modules = path.join(root, 'node_modules');
const SAFE_NAME = /^[A-Za-z0-9_.-]+$/;
const SAFE_PATH = /^[A-Za-z0-9_.\/@-]+$/;

function packageDirs() {
  const out = [];
  let entries;
  try { entries = fs.readdirSync(modules, { withFileTypes: true }); } catch (e) { return out; }
  for (const e of entries) {
    if (!e.isDirectory() || e.name.startsWith('.')) continue;
    if (e.name.startsWith('@')) {
      let inner = [];
      try { inner = fs.readdirSync(path.join(modules, e.name), { withFileTypes: true }); } catch (_) {}
      for (const i of inner) if (i.isDirectory()) out.push(e.name + '/' + i.name);
    } else {
      out.push(e.name);
    }
  }
  return out;
}

const lines = [];
const seen = new Set();
for (const pkg of packageDirs()) {
  let json;
  try { json = JSON.parse(fs.readFileSync(path.join(modules, pkg, 'package.json'), 'utf8')); } catch (_) { continue; }
  let bins = json.bin;
  if (!bins) continue;
  if (typeof bins === 'string') bins = { [String(json.name || pkg).split('/').pop()]: bins };
  for (const name of Object.keys(bins)) {
    const rel = path.posix.normalize(pkg + '/' + String(bins[name]).replace(/^\.\//, ''));
    if (!SAFE_NAME.test(name) || !SAFE_PATH.test(rel) || rel.includes('..') || seen.has(name)) continue;
    seen.add(name);
    lines.push(name + ' ' + rel);
  }
}

try {
  fs.writeFileSync(path.join(modules, '.vscodroid-bins'), lines.join('\n') + (lines.length ? '\n' : ''));
} catch (_) { /* no node_modules yet: nothing to describe */ }

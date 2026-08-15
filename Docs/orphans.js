// Whole-drive orphan sweep: anything on the stick the launcher does not use.
'use strict';
const fs = require('fs');
const path = require('path');
const BASE = 'D:\\';
const s = fs.readFileSync(path.join(BASE, 'Lazarus.hta'), 'utf8');

function slice(src, name, open, close) {
  const st = src.indexOf('var ' + name + ' = ' + open);
  if (st < 0) return null;
  const from = src.indexOf(open, st);
  let d = 0, q = null, esc = false;
  for (let i = from; i < src.length; i++) {
    const c = src[i];
    if (q) { if (esc) esc = false; else if (c === '\\') esc = true; else if (c === q) q = null; continue; }
    if (c === '"' || c === "'") { q = c; continue; }
    if (c === open) d++;
    else if (c === close) { d--; if (!d) return src.slice(from, i + 1); }
  }
  return null;
}
const DATA = JSON.parse(slice(s, 'DATA', '[', ']'));
const ICON = JSON.parse(slice(s, 'ICON', '{', '}'));

const usedFolders = new Set();
const usedIsos = new Set();
for (const [, kids] of DATA) {
  for (const [, rel] of kids) {
    if (/\.iso$/i.test(rel)) usedIsos.add(rel.toLowerCase());
    else usedFolders.add(rel.split('\\').slice(0, 2).join('\\').toLowerCase());
  }
}

console.log('=== Tools\\ folders not referenced by any entry ===');
let orphanMB = 0;
for (const d of fs.readdirSync(path.join(BASE, 'Tools'), { withFileTypes: true })) {
  if (!d.isDirectory()) continue;
  const rel = 'Tools\\' + d.name;
  if (usedFolders.has(rel.toLowerCase())) continue;
  let sz = 0;
  const walk = p => { for (const e of fs.readdirSync(p, { withFileTypes: true })) {
    const q = path.join(p, e.name);
    if (e.isDirectory()) walk(q); else { try { sz += fs.statSync(q).size; } catch (x) {} } } };
  try { walk(path.join(BASE, rel)); } catch (x) {}
  orphanMB += sz / 1048576;
  console.log('  ' + (sz / 1048576).toFixed(1).padStart(8) + ' MB  ' + rel);
}
if (!orphanMB) console.log('  (none)');

console.log('\n=== stray files directly in Tools\\ (should be none) ===');
for (const d of fs.readdirSync(path.join(BASE, 'Tools'), { withFileTypes: true })) {
  if (d.isFile()) console.log('  ' + d.name);
}

console.log('\n=== Icons\\ PNGs not referenced by ICON ===');
const usedIcons = new Set(Object.values(ICON).map(v => (v + '.png').toLowerCase()));
let io = 0;
for (const f of fs.readdirSync(path.join(BASE, 'Icons'))) {
  if (!usedIcons.has(f.toLowerCase())) { console.log('  ' + f); io++; }
}
if (!io) console.log('  (none)');

console.log('\n=== ICON keys with no matching DATA entry ===');
const names = new Set();
for (const [, kids] of DATA) for (const t of kids) names.add(t[0]);
const ko = Object.keys(ICON).filter(k => !names.has(k));
console.log(ko.length ? '  ' + ko.join(', ') : '  (none)');

console.log('\n=== ISO files not in the launcher ===');
const isoRoot = path.join(BASE, 'ISO');
const walkIso = (p, pre) => { for (const e of fs.readdirSync(p, { withFileTypes: true })) {
  const q = path.join(p, e.name), rel = pre + '\\' + e.name;
  if (e.isDirectory()) walkIso(q, rel);
  else if (!usedIsos.has(rel.toLowerCase())) console.log('  ' + rel + '  ' + (fs.statSync(q).size / 1048576).toFixed(0) + ' MB');
} };
walkIso(isoRoot, 'ISO');

console.log('\n=== files at drive root ===');
for (const e of fs.readdirSync(BASE, { withFileTypes: true })) {
  if (e.isFile()) console.log('  ' + e.name);
}
console.log('\n=== Docs\\ ===');
for (const e of fs.readdirSync(path.join(BASE, 'Docs'))) console.log('  ' + e);

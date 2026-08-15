// Static validator for D:\Lazarus.hta
// An HTA cannot be inspected visually, so parse its data tables and assert
// against the real filesystem instead. See wiki/concepts/lazarus-usb-toolkit.md
'use strict';
const fs = require('fs');
const path = require('path');

const BASE = process.argv[2] || 'D:\\';
const HTA = path.join(BASE, 'Lazarus.hta');
const src = fs.readFileSync(HTA, 'utf8');

function grab(name, open, close) {
  const start = src.indexOf('var ' + name + ' = ' + open);
  if (start === -1) throw new Error('could not find table: ' + name);
  const from = src.indexOf(open, start);
  let depth = 0, i = from;
  for (; i < src.length; i++) {
    if (src[i] === open) depth++;
    else if (src[i] === close) { depth--; if (depth === 0) break; }
  }
  return src.slice(from, i + 1);
}

// eval, deliberately: these are JScript array/object literals (unquoted keys,
// HTML entities, trailing-comma tolerance), not JSON, so JSON.parse cannot read
// them. Input is our own launcher file on our own stick, read-only, local-only.
const DATA = eval(grab('DATA', '[', ']'));
const ICON = eval('(' + grab('ICON', '{', '}') + ')');
const TAGDEF = eval('(' + grab('TAGDEF', '{', '}') + ')');

const MAX_DESC = 269;   // longest proven to fit the fixed 212px detail pane
const MAX_PURPOSE = 44;

const problems = [];
const entries = [];
const seenIcons = {};

for (const [group, kids] of DATA) {
  for (const [name, rel, purpose, desc, tag] of kids) {
    entries.push({ group, name, rel, purpose, desc, tag });

    const full = path.join(BASE, rel);
    let stat = null;
    try { stat = fs.statSync(full); } catch (e) { /* missing */ }
    if (!stat) problems.push(['MISSING FILE', name, rel]);
    else if (stat.isDirectory()) problems.push(['POINTS AT FOLDER, build() needs a FILE', name, rel]);

    if (desc.length > MAX_DESC) problems.push(['DESC ' + desc.length + ' > ' + MAX_DESC + ' (will clip)', name, '']);
    if (purpose.length > MAX_PURPOSE) problems.push(['PURPOSE ' + purpose.length + ' > ' + MAX_PURPOSE, name, '']);
    if (/<[a-z/]/i.test(desc)) problems.push(['ANGLE BRACKET in desc (innerHTML eats it)', name, '']);
    if (tag && !TAGDEF[tag]) problems.push(['UNDEFINED TAG "' + tag + '"', name, '']);

    if (ICON[name]) {
      seenIcons[name] = true;
      const png = path.join(BASE, 'Icons', ICON[name] + '.png');
      if (!fs.existsSync(png)) problems.push(['MISSING ICON PNG', name, 'Icons\\' + ICON[name] + '.png']);
    }
  }
}

// Icons defined for entries that no longer exist in DATA = dropped tools.
const orphanIcons = Object.keys(ICON).filter(k => !seenIcons[k]);

// Tool folders physically present but referenced by no DATA entry.
const referenced = new Set(entries.map(e => e.rel.split('\\').slice(0, 2).join('\\').toLowerCase()));
let unlisted = [];
try {
  unlisted = fs.readdirSync(path.join(BASE, 'Tools'), { withFileTypes: true })
    .filter(d => d.isDirectory())
    .map(d => 'Tools\\' + d.name)
    .filter(p => !referenced.has(p.toLowerCase()));
} catch (e) { /* no Tools dir */ }

const isos = entries.filter(e => e.group === 'Boot ISOs').length;
console.log('Lazarus.hta at ' + HTA);
console.log('  entries      : ' + entries.length + '  (' + (entries.length - isos) + ' tools + ' + isos + ' ISOs)');
console.log('  groups       : ' + DATA.length);
console.log('  icons mapped : ' + Object.keys(ICON).length);
console.log('  longest desc : ' + Math.max(...entries.map(e => e.desc.length)) + ' / ' + MAX_DESC);
console.log('  longest purp : ' + Math.max(...entries.map(e => e.purpose.length)) + ' / ' + MAX_PURPOSE);
console.log('');

if (problems.length) {
  console.log('PROBLEMS (' + problems.length + '):');
  for (const [what, who, where] of problems) console.log('  [' + what + '] ' + who + (where ? '  ->  ' + where : ''));
} else {
  console.log('PROBLEMS: none. Every path, icon, tag and length checks out.');
}

if (orphanIcons.length) {
  console.log('');
  console.log('ORPHAN ICONS (icon extracted, but tool is NOT in the launcher menu):');
  for (const k of orphanIcons) console.log('  ' + k + '  ->  Icons\\' + ICON[k] + '.png');
}

if (unlisted.length) {
  console.log('');
  console.log('TOOL FOLDERS ON DISK BUT NOT IN THE LAUNCHER:');
  for (const u of unlisted) console.log('  ' + u);
}

process.exit(problems.length ? 1 : 0);

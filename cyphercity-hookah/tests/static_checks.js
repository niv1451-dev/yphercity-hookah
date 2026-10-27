/* Cross-checks between files that no single test can see:
   manifest ↔ files, NUI ↔ client callbacks, client ↔ server callbacks and events,
   translation keys (Lua + NUI, Hebrew + English), icons used by the config.
   Run: node tests/static_checks.js */
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ROOT = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(ROOT, file), 'utf8');
const exists = (file) => fs.existsSync(path.join(ROOT, file));
const stripLuaComments = (text) => text.replace(/--\[\[[\s\S]*?\]\]/g, '').replace(/--[^\n]*/g, '');
const list = (dir) => fs.readdirSync(path.join(ROOT, dir)).filter((f) => f.endsWith('.lua')).map((f) => dir + '/' + f);
const all = (re, text, group = 1) => Array.from(text.matchAll(re), (m) => m[group]);

let failures = 0;
let checks = 0;
function check(name, problems) {
  checks++;
  if (problems.length) {
    failures++;
    console.log('  \x1b[31m✘ ' + name + '\x1b[0m');
    problems.slice(0, 20).forEach((p) => console.log('      ' + p));
  } else {
    console.log('  \x1b[32m✔\x1b[0m ' + name);
  }
}

console.log('\n\x1b[1mStatic cross-checks\x1b[0m');

// ── manifest ────────────────────────────────────────────
const manifest = read('fxmanifest.lua');
const block = (name) => {
  const m = manifest.match(new RegExp(name + '\\s*\\{([\\s\\S]*?)\\}'));
  return m ? all(/'([^']+)'/g, m[1]) : [];
};
const shared = block('shared_scripts');
const server = block('server_scripts');
const client = block('client_scripts');
const files = block('files');
check('every script listed in fxmanifest.lua exists', [...shared, ...server, ...client].filter((f) => !exists(f)).map((f) => 'missing: ' + f));
check('every NUI file pattern in fxmanifest.lua matches files', files.filter((pattern) => {
  if (!pattern.includes('*')) return !exists(pattern);
  const dir = path.dirname(pattern);
  const ext = path.extname(pattern);
  return !exists(dir) || !fs.readdirSync(path.join(ROOT, dir)).some((f) => f.endsWith(ext));
}).map((f) => 'no match: ' + f));
const uiPage = (manifest.match(/ui_page\s+'([^']+)'/) || [])[1];
check('ui_page exists and is listed in files', !uiPage || !exists(uiPage) || !files.includes(uiPage) ? ['ui_page problem: ' + uiPage] : []);
const luaOnDisk = [...list('client'), ...list('server'), ...list('shared'), ...list('bridge'), 'config.lua', 'config_server.lua'];
check('no Lua file is forgotten in fxmanifest.lua', luaOnDisk.filter((f) => ![...shared, ...server, ...client].includes(f)).map((f) => 'not loaded: ' + f));

// ── sources ──────────────────────────────────────────────
const src = (files) => files.map((f) => stripLuaComments(read(f))).join('\n');
const serverSrc = src([...server, ...shared]);
const clientSrc = src([...client, ...shared]);
const appJs = read('html/app.js');
const html = read('html/index.html');

// NUI → client
const nuiCallbacks = new Set(all(/RegisterNUICallback\('(\w+)'/g, clientSrc));
const forwardBlock = (clientSrc.match(/local FORWARD = \{([\s\S]*?)\}/) || [])[1] || '';
all(/'(\w+)'/g, forwardBlock).forEach((n) => nuiCallbacks.add(n));
const posted = new Set([...all(/post\('(\w+)'/g, appJs), ...all(/call\('(\w+)'/g, appJs)]);
check('every NUI request has a client NUI callback', [...posted].filter((n) => !nuiCallbacks.has(n)).map((n) => 'NUI posts "' + n + '" but no RegisterNUICallback'));

// client → server callbacks
const registered = new Set(all(/Callback\.Register\('(\w+)'/g, serverSrc));
const awaited = new Set([...all(/Callback\.Await\('(\w+)'/g, clientSrc), ...all(/'(\w+)'/g, forwardBlock)]);
check('every client callback is registered on the server', [...awaited].filter((n) => !registered.has(n)).map((n) => 'client awaits "' + n + '" — no Callback.Register'));
check('every server callback is used by the client', [...registered].filter((n) => !awaited.has(n)).map((n) => 'server registers "' + n + '" — never called'));

// server → client events
const toClient = new Set(all(/TriggerClientEvent\('(cyphercity-hookah:client:\w+)'/g, serverSrc));
toClient.add('cyphercity-hookah:client:notify');
const clientEvents = new Set(all(/RegisterNetEvent\('(cyphercity-hookah:client:\w+)'/g, clientSrc));
const notifyEvent = clientSrc.includes("local EVENT = 'cyphercity-hookah:client:notify'") && clientSrc.includes('RegisterNetEvent(EVENT');
if (notifyEvent) clientEvents.add('cyphercity-hookah:client:notify');
check('every server → client event has a client handler', [...toClient].filter((e) => !clientEvents.has(e)).map((e) => 'no handler: ' + e));
check('every client handler has a server sender', [...clientEvents].filter((e) => !toClient.has(e)).map((e) => 'never sent: ' + e));

// Lua translations
const localesLua = read('shared/locales.lua');
const section = (lang) => {
  const start = localesLua.indexOf('Locales.' + lang + ' = {');
  const end = localesLua.indexOf('\n}', start);
  return new Set(all(/^\s{4}(\w+)\s*=/gm, localesLua.slice(start, end)));
};
const he = section('he');
const en = section('en');
check('Lua translations: Hebrew and English have the same keys', [
  ...[...he].filter((k) => !en.has(k)).map((k) => 'missing in en: ' + k),
  ...[...en].filter((k) => !he.has(k)).map((k) => 'missing in he: ' + k),
]);
const allLua = src([...shared, ...server, ...client]);
const usedKeys = new Set([...all(/\bL\('(\w+)'/g, allLua), ...all(/fail\('(\w+)'/g, allLua), ...all(/return false, '(\w+)'/g, allLua), ...all(/return nil, '(\w+)'/g, allLua)]);
['status_free', 'status_reserved', 'status_occupied', 'status_cleaning', 'account_cash', 'account_bank'].forEach((k) => usedKeys.add(k));
const internal = new Set(['no_player', 'no_balance', 'error', 'rejected', 'not_deducted', 'unsupported', 'invalid_amount']);
check('every message / error code used in Lua has a translation', [...usedKeys].filter((k) => !k.endsWith('_') && !he.has(k) && !internal.has(k)).map((k) => 'no translation: ' + k));

// NUI translations
const sandbox = { window: {} };
vm.runInNewContext(read('html/locale.js'), sandbox);
const nuiHe = sandbox.window.CCH_LOCALES.he;
const nuiEn = sandbox.window.CCH_LOCALES.en;
check('NUI translations: Hebrew and English have the same keys', [
  ...Object.keys(nuiHe).filter((k) => !(k in nuiEn)).map((k) => 'missing in en: ' + k),
  ...Object.keys(nuiEn).filter((k) => !(k in nuiHe)).map((k) => 'missing in he: ' + k),
]);
const nuiKeys = new Set([...all(/\bt\('(\w+)'/g, appJs), ...all(/data-t="(\w+)"/g, html), ...all(/data-t-title="(\w+)"/g, html)]);
const families = {
  tab_: ['host', 'menu', 'orders', 'bill', 'staff'],
  status_: ['free', 'reserved', 'occupied', 'cleaning'],
  order_: ['new', 'preparing', 'serving', 'completed', 'cancelled'],
  pay_: ['unpaid', 'processing', 'paid', 'void', 'refunded', 'refund_pending', 'free'],
  menu_sort_: ['recommended', 'price_asc', 'price_desc', 'name'],
  staff_col_: ['new', 'preparing', 'serving'],
  staff_: ['orders', 'tables', 'sales', 'stock', 'logs', 'business'],
  role_: ['manager', 'cashier', 'waiter', 'host'],
  mode_: ['auto', 'staff', 'hybrid'],
  log_: ['order', 'payment', 'table', 'hookah', 'staff', 'security', 'system'],
};
Object.entries(families).forEach(([prefix, names]) => names.forEach((n) => nuiKeys.add(prefix + n)));
// tags shown as filter chips come from config.lua
const configText = read('config.lua');
Array.from(configText.matchAll(/tags\s*=\s*\{([^}]*)\}/g)).forEach((m) => all(/'(\w+)'/g, m[1]).forEach((tag) => nuiKeys.add('tag_' + tag)));
check('every NUI text key exists', [...nuiKeys].filter((k) => !k.endsWith('_') && !(k in nuiHe)).map((k) => 'missing NUI key: ' + k));

// config → icons
const config = read('config.lua');
const icons = new Set(fs.readdirSync(path.join(ROOT, 'html/assets/icons')));
const referenced = new Set([...all(/image\s*=\s*'([^']+)'/g, config), ...all(/icon\s*=\s*'([^']+\.svg)'/g, config), ...all(/ICON_PATH\}([\w.]+\.svg)/g, appJs)]);
referenced.add('logo.svg');
referenced.add('platter.svg');
check('every icon referenced by config.lua / app.js exists', [...referenced].filter((i) => !icons.has(i)).map((i) => 'missing icon: ' + i));

// no secrets in shared config / no external runtime URLs in the NUI
check('config.lua (sent to players) contains no webhook URLs', /discord(app)?\.com\/api\/webhooks/i.test(config) ? ['webhook URL found in config.lua'] : []);
const externalRefs = all(/(?:src|href)=["'](https?:\/\/[^"']+)/g, html + appJs + read('html/style.css'));
check('NUI loads no external resources at runtime', externalRefs.map((u) => 'external: ' + u));

console.log(`\n${checks - failures} passed, ${failures} failed`);
process.exit(failures ? 1 : 0);

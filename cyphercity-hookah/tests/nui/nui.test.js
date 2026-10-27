/* NUI end-to-end test in Chromium (Playwright).
   Run: node tests/nui/nui.test.js [screenshotDir]
   The NUI runs against tests/nui/mock.js (a simulated server that uses the real
   catalog exported from config.lua). */
'use strict';
const path = require('path');
const fs = require('fs');
const assert = require('assert');
const { chromium } = require('playwright');

const ROOT = path.resolve(__dirname, '..', '..');
const PAGE = 'file://' + path.join(ROOT, 'html', 'index.html');
const SHOTS = process.argv[2] ? path.resolve(process.argv[2]) : null;

global.window = {};
require(path.join(__dirname, 'mock-data.js'));
const DATA = global.window.CCH_MOCK_DATA;
// Lua encodes empty tables as {} — normalise the sample data the same way the NUI does
const arr = (v) => (Array.isArray(v) ? v : v && typeof v === 'object' ? Object.values(v) : []);
DATA.catalog.products.forEach((p) => { p.tags = arr(p.tags); if (p.allowedFlavors) p.allowedFlavors = arr(p.allowedFlavors); });
const product = (id) => DATA.catalog.products.find((p) => p.id === id);
const flavor = (id) => DATA.catalog.flavors.find((f) => f.id === id);

let passed = 0;
let failed = 0;
async function test(name, fn) {
  try {
    await fn();
    passed++;
    console.log('  \x1b[32m✔\x1b[0m ' + name);
  } catch (err) {
    failed++;
    console.log('  \x1b[31m✘ ' + name + '\x1b[0m\n      ' + String(err && err.stack || err).split('\n').slice(0, 4).join('\n      '));
  }
}

async function shot(page, name) {
  if (!SHOTS) return;
  fs.mkdirSync(SHOTS, { recursive: true });
  await page.mouse.move(0, 0); // no hover effects in the pictures
  await page.waitForTimeout(450); // let entrance animations finish
  await page.screenshot({ path: path.join(SHOTS, name + '.jpg'), type: 'jpeg', quality: 86 });
}

const numberIn = (text) => Number(String(text).replace(/[^\d]/g, ''));

(async () => {
  const browser = await chromium.launch();
  const context = await browser.newContext({ viewport: { width: 1920, height: 1080 } });
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });

  async function open(query) {
    await page.goto(PAGE + (query || ''));
    await page.waitForSelector('#app:not([hidden]) .panel');
    await page.waitForTimeout(250);
  }

  console.log('\n\x1b[1mNUI (Chromium)\x1b[0m');

  await test('loads in Hebrew RTL with all tabs, categories and products', async () => {
    await open('?panel=menu');
    assert.strictEqual(await page.getAttribute('html', 'dir'), 'rtl');
    assert.strictEqual(await page.locator('.tab').count(), 5);
    assert.strictEqual(await page.locator('.category').count(), DATA.catalog.categories.length + 1);
    assert.strictEqual(await page.locator('.product').count(), DATA.catalog.products.length);
    assert.ok((await page.textContent('.tabs')).includes('תפריט'));
    assert.strictEqual((await page.textContent('#brandTitle')).trim(), DATA.business.name, 'business name from config.lua');
    assert.strictEqual(await page.title(), DATA.business.name);
    await shot(page, '01-menu');
  });

  await test('search, category and tag filters', async () => {
    await page.fill('#menuSearch', 'כנפיים');
    await page.waitForTimeout(100);
    const expected = DATA.catalog.products.filter((p) => p.label.includes('כנפיים') || p.description.includes('כנפיים')).length;
    assert.strictEqual(await page.locator('.product').count(), expected);
    await page.fill('#menuSearch', '');
    await page.click('.category[data-id="fried"]');
    assert.strictEqual(await page.locator('.product').count(), DATA.catalog.products.filter((p) => p.category === 'fried').length);
    await page.click('.category[data-id="all"]');
    await page.click('.chip[data-tag="spicy"]');
    assert.strictEqual(await page.locator('.product').count(), DATA.catalog.products.filter((p) => p.tags.includes('spicy')).length);
    await page.click('.chip[data-tag="spicy"]');
  });

  await test('cart: add, change quantity, totals and per-item limits', async () => {
    await page.click('.add-btn[data-id="fries"]');
    await page.click('.add-btn[data-id="fries"]');
    await page.click('.add-btn[data-id="beer_draft"]');
    const total = numberIn(await page.textContent('.cart .total'));
    assert.strictEqual(total, product('fries').price * 2 + product('beer_draft').price);
    for (let i = 0; i < 12; i++) await page.click('.add-btn[data-id="beer_draft"]');
    const qty = Number(await page.locator('.cart-line').nth(1).locator('.stepper span').textContent());
    assert.strictEqual(qty, product('beer_draft').maxQty, 'capped at maxQty');
    assert.ok(await page.locator('.toast.warning').count() > 0, 'limit toast shown');
    await page.locator('.cart-line').nth(1).locator('[data-delta="-1"]').click();
    assert.strictEqual(Number(await page.locator('.cart-line').nth(1).locator('.stepper span').textContent()), product('beer_draft').maxQty - 1);
  });

  await test('hookah flavour picker respects the flavour limit and prices the mix', async () => {
    await page.click('.category[data-id="hookah"]');
    await page.click('.add-btn[data-id="hookah_mix"]');
    await page.waitForSelector('.modal .flavor-grid');
    await page.click('.flavor[data-id="peach"]');
    await page.click('.flavor[data-id="mango"]');
    assert.ok(await page.locator('.flavor[data-id="watermelon"]').isDisabled(), 'third flavour disabled');
    await shot(page, '02-flavor-picker');
    await page.click('[data-action="flavorAdd"]');
    const line = page.locator('.cart-line', { hasText: product('hookah_mix').label });
    const price = product('hookah_mix').price + flavor('peach').price + flavor('mango').price;
    assert.strictEqual(numberIn(await line.locator('.ln-total').textContent()), price);
    await page.click('.add-btn[data-id="hookah_fruit"]');
    const allowed = await page.locator('.modal .flavor').count();
    assert.strictEqual(allowed, product('hookah_fruit').allowedFlavors.length, 'only allowed flavours offered');
    await page.keyboard.press('Escape');
    assert.strictEqual(await page.locator('#modal:not([hidden])').count(), 0, 'ESC closes the modal first');
    assert.strictEqual(await page.locator('#app:not([hidden])').count(), 1, 'app still open');
    await shot(page, '03-cart');
  });

  await test('sending an order switches to the order tracker', async () => {
    await page.click('[data-action="placeOrder"]');
    await page.waitForSelector('.order-card');
    assert.ok(await page.locator('.toast.success').count() > 0);
    assert.ok((await page.textContent('.tab.active')).includes('ההזמנות'));
    assert.ok(await page.locator('.hookah-card').count() >= 1);
    await page.waitForTimeout(6200);
    await shot(page, '04-orders');
  });

  await test('bill: tip changes the total, payment requires confirmation', async () => {
    await page.click('.tab[data-panel="bill"]');
    await page.waitForSelector('.receipt');
    const subtotal = numberIn(await page.locator('.receipt-sum .total-row').first().locator('span').last().textContent());
    await page.click('.option[data-p="10"]');
    const grand = numberIn(await page.textContent('.receipt-sum .grand'));
    assert.strictEqual(grand, subtotal + Math.round(subtotal * 0.1));
    await page.click('.option[data-id="bank"]');
    await shot(page, '05-bill');
    await page.click('[data-action="confirmPay"]');
    await page.waitForSelector('.modal');
    await shot(page, '06-pay-confirm');
    await page.click('[data-action="confirmYes"]');
    await page.waitForSelector('.paid-state');
    await shot(page, '07-paid');
  });

  await test('host panel: party size and table request', async () => {
    await open('?panel=host&scenario=new');
    assert.strictEqual(await page.locator('.floor-table').count(), DATA.tables.length);
    await page.click('.party [data-n="4"]');
    await shot(page, '08-host');
    await page.click('[data-action="requestTable"]');
    await page.waitForSelector('.my-table');
    assert.ok((await page.textContent('.my-table')).includes('שולחן'));
    await shot(page, '09-host-table');
  });

  await test('staff panel: kanban, tables, sales and log', async () => {
    await open('?panel=staff');
    await page.waitForSelector('.kanban');
    assert.strictEqual(await page.locator('.kanban').first().locator('.kanban-col').count(), 3);
    await shot(page, '10-staff-orders');
    await page.click('.chip[data-tab="tables"]');
    assert.strictEqual(await page.locator('.table-row').count(), DATA.tables.length);
    await shot(page, '11-staff-tables');
    await page.click('.chip[data-tab="sales"]');
    await page.waitForSelector('.stats .stat');
    assert.strictEqual(await page.locator('.stat').count(), 4);
    await page.waitForTimeout(700);
    await shot(page, '12-staff-sales');
    await page.click('.chip[data-tab="logs"]');
    await page.waitForSelector('.log-row');
  });

  await test('kitchen note and "call waiter" from the customer screens', async () => {
    await open('?panel=menu');
    await page.click('.add-btn[data-id="cola"]');
    await page.fill('#orderNote', 'בלי קרח');
    await page.click('.add-btn[data-id="water"]');
    assert.strictEqual(await page.inputValue('#orderNote'), 'בלי קרח', 'note kept while the cart changes');
    await page.click('[data-action="placeOrder"]');
    await page.waitForSelector('.order-card .order-note');
    assert.ok((await page.textContent('.order-card .order-note')).includes('בלי קרח'));
    await page.click('[data-action="callWaiter"]');
    await page.waitForSelector('.toast.success');
  });

  await test('staff: a waiter takes an order for a table from the tables tab', async () => {
    await open('?panel=staff');
    await page.click('.chip[data-tab="tables"]');
    await page.click('[data-action="staffTakeOrder"]');
    await page.waitForSelector('.notice.staff-order');
    await page.click('.add-btn[data-id="tea_nana"]');
    await page.fill('#orderNote', 'עם הרבה נענע');
    assert.ok((await page.textContent('[data-action="placeOrder"]')).includes('שליחה ל'));
    await shot(page, '17-staff-take-order');
    await page.click('[data-action="placeOrder"]');
    await page.waitForSelector('.kanban');
    const tickets = await page.textContent('.kanban');
    assert.ok(tickets.includes('עם הרבה נענע') && tickets.includes('דניאל'), 'ticket shows the note and the waiter');
  });

  await test('E-prompt, context menu (number keys) and toasts outside the panel', async () => {
    await open('?panel=menu');
    await page.keyboard.press('Escape');
    assert.strictEqual(await page.locator('#app[hidden]').count(), 1, 'ESC closes the app');
    const posted = [];
    await page.exposeFunction('__recordPost', (name, data) => posted.push([name, data]));
    await page.evaluate(() => {
      const original = window.CCH_PREVIEW.post;
      window.CCH.setPost((name, data) => { window.__recordPost(name, data); return original(name, data); });
      window.CCH.handleMessage({ action: 'prompt', data: { show: true, label: 'דבר עם המארחת', more: false } });
      window.CCH.handleMessage({ action: 'toast', data: { message: 'קיבלת את שולחן 3.', type: 'success' } });
    });
    assert.ok(await page.isVisible('#prompt'));
    await page.waitForTimeout(350);
    await shot(page, '13-prompt');
    await page.evaluate(() => window.CCH.handleMessage({ action: 'context', data: { options: [{ index: 1, label: 'שב בשולחן' }, { index: 2, label: 'תפריט' }, { index: 3, label: 'קרא למלצר' }] } }));
    assert.strictEqual(await page.locator('#context button').count(), 3);
    await page.waitForTimeout(350);
    await shot(page, '14-context');
    await page.keyboard.press('2');
    await page.waitForTimeout(150);
    assert.ok(posted.some(([name, data]) => name === 'contextSelect' && data.index === 2), 'contextSelect posted');
    assert.ok(await page.locator('#context[hidden]').count() === 1, 'context closed');
  });

  await test('robust to empty Lua tables encoded as {} objects', async () => {
    await open('?panel=orders');
    await page.evaluate(() => window.CCH.handleMessage({ action: 'state', data: { orders: {}, served: {}, hookahs: {}, members: {}, invites: {}, perms: {}, bill: {}, tableId: 1, tableLabel: 'שולחן 1', tableStatus: 'occupied' } }));
    await page.click('.tab[data-panel="host"]');
    await page.click('.tab[data-panel="menu"]');
    await page.click('.tab[data-panel="orders"]');
    assert.ok(await page.locator('.orders-layout').count() === 1);
  });

  await test('layout fits 1280×720 and 4K without horizontal overflow', async () => {
    for (const [w, h, name] of [[1280, 720, '15-menu-720p'], [3840, 2160, '16-menu-4k']]) {
      await page.setViewportSize({ width: w, height: h });
      await open('?panel=menu');
      const overflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
      assert.strictEqual(overflow, false, `overflow at ${w}x${h}`);
      if (w === 1280) await shot(page, name);
    }
    await page.setViewportSize({ width: 1920, height: 1080 });
  });

  await test('placement tool: tools, tables, live status, confirmations and the HUD', async () => {
    await open('?panel=setup');
    assert.strictEqual(await page.locator('.setup-layout').count(), 1, 'setup panel');
    assert.strictEqual(await page.locator('.tab').count(), 1, 'only the placement tab');
    assert.ok(await page.isHidden('#tableBadge'), 'no table badge in setup');
    assert.strictEqual(await page.locator('.tool').count(), 5, 'five tools');
    assert.ok((await page.textContent('.setup-status')).includes('טיוטה'), 'starts as draft');
    assert.strictEqual(await page.locator('.setup-check.missing').count(), 3, 'hostess, waiter, table missing');
    // hostess, waiter
    await page.click('[data-action="setupPlace"]');
    await page.waitForSelector('.toast');
    assert.ok((await page.textContent('#toasts')).includes('המארחת תעמוד כאן'), 'server message shown');
    await page.click('.tool[data-tool="waiter"]');
    assert.ok((await page.textContent('.place-card')).includes('עמדת מלצר'), 'place card follows the tool');
    await page.click('[data-action="setupPlace"]');
    await page.waitForFunction(() => document.querySelectorAll('.setup-side .member-list li button').length === 1);
    // seat tool without a table cannot place
    await page.click('.tool[data-tool="seat"]');
    assert.ok(await page.isDisabled('[data-action="setupPlace"]'), 'needs a table');
    // a new table selects itself and switches to the seat tool
    await page.click('[data-op="table_add"]');
    await page.waitForSelector('.setup-editor');
    assert.ok((await page.inputValue('#setupLabel')).includes('שולחן 1'));
    await page.click('[data-action="setupPlace"]');
    await page.waitForFunction(() => document.querySelector('.setup-status').textContent.includes('ההצבה פעילה'));
    assert.ok((await page.textContent('#toasts')).includes('פועל עכשיו כאן'), 'activation message');
    await page.click('[data-action="setupPlace"]');
    await page.waitForFunction(() => document.querySelectorAll('.seat-chips .chip').length === 2);
    // table editor: height, VIP, rename with Enter
    await page.click('[data-action="setupSeatZ"][data-delta="0.05"]');
    await page.waitForFunction(() => document.querySelector('.se-height .stepper span').textContent.includes('+5'));
    await page.click('[data-action="setupVip"]');
    await page.waitForSelector('.setup-table.active .vip-mark');
    await page.fill('#setupLabel', 'שולחן הספה');
    await page.press('#setupLabel', 'Enter');
    await page.waitForFunction(() => document.querySelector('.setup-table.active .st-name').textContent.includes('הספה'));
    // delete asks first
    await page.click('[data-action="setupRemoveTable"]');
    assert.ok((await page.textContent('#modal')).includes('הספה'), 'confirmation names the table');
    await page.click('#modal [data-action="closeModal"]');
    assert.strictEqual(await page.locator('.setup-table:not(.add)').count(), 1, 'nothing deleted on cancel');
    await page.click('[data-action="setupReset"]');
    assert.ok(await page.isVisible('#modal .btn.danger'), 'reset needs a confirmation');
    await page.click('#modal [data-action="closeModal"]');
    // ESC closes the menu, the HUD stays while placing
    await page.keyboard.press('Escape');
    await page.waitForSelector('#setupHud:not([hidden])');
    const hud = await page.textContent('#setupHud');
    assert.ok(hud.includes('כיסא') && hud.includes('הספה') && hud.includes('F7'), 'HUD: tool, table and keys');
    await page.evaluate(() => window.CCH.handleMessage({ action: 'setup', data: Object.assign({}, window.CCH_PREVIEW.setup, { sitting: true, setup: window.CCH_PREVIEW.setupState }) }));
    assert.ok((await page.textContent('#setupHud')).includes('לקום'), 'HUD during the test sit');
    await page.evaluate(() => window.CCH.handleMessage({ action: 'setup', data: Object.assign({}, window.CCH_PREVIEW.setup, { active: false, setup: window.CCH_PREVIEW.setupState }) }));
    assert.ok(await page.isHidden('#setupHud'), 'HUD hidden when the mode ends');
  });

  await test('placement tool with a finished layout (screenshots) and a busy table', async () => {
    await open('?panel=setup&layout=full');
    assert.ok((await page.textContent('.setup-status')).includes('ההצבה פעילה'));
    assert.strictEqual(await page.locator('.setup-table .status.occupied').count(), 1, 'table in use is marked');
    await shot(page, '18-setup-menu');
    await page.evaluate(() => { document.querySelector('.setup-layout').scrollTop = 99999; });
    await shot(page, '20-setup-table');
    await page.evaluate(() => { document.querySelector('.setup-layout').scrollTop = 0; });
    await page.click('.setup-table[data-id="2"]');
    await page.click('[data-action="setupTestSit"]');
    assert.strictEqual(await page.locator('#app[hidden]').count(), 1, 'test sit closes the menu');
    await page.waitForTimeout(100); // the preview answers the test sit asynchronously
    await page.evaluate(() => {
      Object.assign(window.CCH_PREVIEW.setup, { sitting: false, tool: 'seat', tableId: 3 });
      window.CCH.handleMessage({ action: 'setup', data: Object.assign({}, window.CCH_PREVIEW.setup, { setup: window.CCH_PREVIEW.setupState }) });
    });
    await page.waitForSelector('#setupHud:not([hidden])');
    await shot(page, '19-setup-hud');
    await page.evaluate(() => window.CCH.handleMessage({ action: 'open', data: { panel: 'setup', context: Object.assign({}, window.CCH_PREVIEW.setup, { setup: window.CCH_PREVIEW.setupState }) } }));
    await page.click('.setup-table[data-id="2"]');
    await page.click('[data-action="setupDo"][data-op="seat_remove"]');
    await page.waitForFunction(() => document.querySelector('#toasts').textContent.includes('בשימוש'));
    await page.setViewportSize({ width: 1280, height: 720 });
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    assert.strictEqual(overflow, false, 'setup fits 720p');
    await page.setViewportSize({ width: 1920, height: 1080 });
  });

  await test('no JavaScript errors were thrown', async () => {
    assert.deepStrictEqual(errors, []);
  });

  await browser.close();
  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})();

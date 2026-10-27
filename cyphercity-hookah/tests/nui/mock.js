/* Browser preview of the NUI (not loaded in game).
   Simulates the Lua side with the real catalog exported from config.lua
   (tests/nui/mock-data.js). Open html/index.html in a browser:
     index.html?panel=menu            (default)
     index.html?panel=host&scenario=new
     index.html?panel=orders | bill | staff
     index.html?panel=setup              (placement tool, empty)
     index.html?panel=setup&layout=full  (placement tool with a finished layout)
*/
(function () {
  'use strict';
  const D = window.CCH_MOCK_DATA;
  const CCH = window.CCH;
  if (!D || !CCH) return;

  const params = new URLSearchParams(location.search);
  const scenario = params.get('scenario') || 'seated';
  const startPanel = params.get('panel') || 'menu';
  const products = new Map(D.catalog.products.map((p) => [p.id, p]));
  const flavors = new Map(D.catalog.flavors.map((f) => [f.id, f]));
  const fill = (text, vars) => Object.keys(vars || {}).reduce((t, k) => t.split('%' + k + '%').join(vars[k]), text || '');
  const gap = D.currency.space ? '\u00A0' : '';
  const money = (n) => (D.currency.position === 'after' ? n + gap + D.currency.symbol : D.currency.symbol + gap + n);
  const wait = (ms) => new Promise((r) => setTimeout(r, ms));

  const S = {
    nextOrder: 41,
    orders: [],
    served: [],
    hookahs: [],
    tableId: null,
    seat: null,
    tableStatus: null,
    cash: 850,
    bank: 12400,
    staffLog: [],
    businessOpen: true,
  };
  const tables = JSON.parse(JSON.stringify(D.tables));
  [1, 2, 5].forEach((id) => { const t = tables.find((x) => x.id === id); t.status = 'occupied'; t.members = 2; t.seated = 2; t.occupiedSeats[0] = t.occupiedSeats[1] = true; });
  tables.find((x) => x.id === 4).status = 'cleaning';
  tables.find((x) => x.id === 6).status = 'reserved';

  function dispatch(action, data) { CCH.handleMessage({ action, data }); }

  function priceLine(line) {
    const p = products.get(line.id);
    let unit = p.price;
    (line.flavors || []).forEach((f) => { unit += (flavors.get(f) || { price: 0 }).price; });
    return { id: p.id, kind: p.kind, label: p.label, qty: line.qty, unitPrice: unit, total: unit * line.qty, flavors: line.flavors || [], flavorLabels: (line.flavors || []).map((f) => flavors.get(f).label) };
  }

  function view(order) {
    return Object.assign({}, order, { age: Math.floor((Date.now() - order.created) / 1000), mine: order.mine !== false });
  }

  function me() {
    const unpaid = S.orders.filter((o) => o.paymentStatus === 'unpaid' && o.status !== 'cancelled');
    const table = tables.find((t) => t.id === S.tableId);
    return {
      serverId: 1,
      tableId: S.tableId,
      tableLabel: table ? table.label : null,
      tableStatus: S.tableStatus,
      seat: S.seat,
      isOwner: !!S.tableId,
      reservedFor: S.tableStatus === 'reserved' ? 170 : null,
      members: S.tableId ? [{ id: 1, name: 'נועם כהן', seated: S.seat !== null, owner: true, me: true }, { id: 7, name: 'שירה לוי', seated: true, owner: false }] : [],
      invites: [],
      orders: S.orders.map(view).reverse(),
      served: S.served,
      hookahs: S.hookahs.map((h) => Object.assign({}, h, { remaining: Math.max(0, Math.floor((h.expires - Date.now()) / 1000)) })),
      bill: { personal: unpaid.filter((o) => o.mine !== false).reduce((s, o) => s + o.subtotal, 0), table: unpaid.reduce((s, o) => s + o.subtotal, 0) },
      staffRole: 'manager',
      perms: ['view_tables', 'reserve_table', 'clean_table', 'seat_guest', 'release_table', 'view_orders', 'update_order', 'take_order', 'cancel_order', 'request_payment', 'view_sales', 'manage_stock', 'toggle_business', 'view_logs'],
      businessOpen: S.businessOpen,
    };
  }

  function push() { dispatch('state', me()); dispatch('staff', staff()); }

  function staff() {
    const st = me();
    return {
      role: 'manager',
      perms: st.perms,
      businessOpen: S.businessOpen,
      businessManualOpen: S.businessOpen,
      mode: D.settings.ordersMode,
      orders: S.orders.filter((o) => ['new', 'preparing', 'serving'].includes(o.status) || o.paymentStatus === 'unpaid').map(view),
      tables: tables.map((t) => ({
        id: t.id, label: t.label, capacity: t.capacity, vip: t.vip, status: t.status,
        owner: t.status === 'occupied' ? (t.id === S.tableId ? 'נועם כהן' : 'אורח #' + t.id) : null,
        members: t.status === 'occupied' ? [{ id: 1, name: 'נועם כהן', unpaid: 0 }, { id: 7, name: 'שירה לוי', unpaid: 0 }] : [],
        unpaid: t.id === S.tableId ? st.bill.table : (t.status === 'occupied' ? 86 : 0),
        reservedFor: t.status === 'reserved' ? 'משפחת אברהם' : null,
        timer: t.status === 'cleaning' ? 32 : (t.status === 'reserved' ? 1500 : null),
        openFor: t.status === 'occupied' ? 1860 : null,
        hookahs: t.status === 'occupied' ? 1 : 0,
      })),
      stock: null,
    };
  }

  function addOrder(lines, opts) {
    const priced = lines.map(priceLine);
    const order = {
      id: S.nextOrder++, kind: 'order', tableId: S.tableId, tableLabel: (tables.find((t) => t.id === S.tableId) || {}).label,
      customer: (opts && opts.customer) || 'נועם כהן', mine: !(opts && opts.customer), lines: priced,
      subtotal: priced.reduce((s, l) => s + l.total, 0), status: (opts && opts.status) || 'new', paymentStatus: 'unpaid',
      created: Date.now() - ((opts && opts.age) || 0) * 1000, auto: true, eta: 40,
      note: (opts && opts.note) || null, placedBy: (opts && opts.placedBy) || null,
    };
    S.orders.push(order);
    return order;
  }

  function progress(order) {
    const steps = [['preparing', 1500], ['serving', 3500], ['completed', 5500]];
    steps.forEach(([status, ms]) => setTimeout(() => {
      if (order.status === 'cancelled') return;
      order.status = status;
      if (status === 'completed') deliver(order);
      push();
    }, ms));
  }

  function deliver(order) {
    order.lines.forEach((l) => {
      const p = products.get(l.id);
      if (p.kind === 'hookah') {
        for (let i = 0; i < l.qty; i++) S.hookahs.push({ id: S.hookahs.length + 1, tableId: S.tableId, spot: S.hookahs.length + 1, typeId: p.id, label: p.label, flavors: l.flavors, flavorLabels: l.flavorLabels, total: p.duration, expires: Date.now() + p.duration * 1000, refreshes: 0, owner: 1 });
      } else {
        const item = S.served.find((x) => x.id === p.id);
        if (item) item.count += l.qty; else S.served.push({ id: p.id, label: p.label, count: l.qty, image: p.image });
      }
    });
  }

  function seat() {
    S.tableId = 3;
    S.seat = 1;
    S.tableStatus = 'occupied';
    const t = tables.find((x) => x.id === 3);
    t.status = 'occupied'; t.members = 2; t.seated = 2; t.occupiedSeats[0] = t.occupiedSeats[1] = true;
  }

  if (scenario !== 'new') {
    seat();
    const first = addOrder([{ id: 'hookah_mix', qty: 1, flavors: ['grape_mint', 'lemon_mint'] }, { id: 'tea_kettle', qty: 1 }], { status: 'completed', age: 900 });
    deliver(first);
    S.hookahs[0].expires = Date.now() + 1180 * 1000;
    addOrder([{ id: 'fries', qty: 2 }, { id: 'wings_buffalo', qty: 1 }, { id: 'beer_draft', qty: 2 }], { status: 'preparing', age: 140 });
    addOrder([{ id: 'edamame_spicy', qty: 1 }, { id: 'arak_grapefruit', qty: 1 }], { status: 'new', age: 25, customer: 'שירה לוי', note: 'בלי קרח בערק' });
  }

  const ok = (data, message) => ({ ok: true, data, message });
  const fail = (code, message) => ({ ok: false, code, message });

  // ── placement tool (/hookahsetup) ──
  const B = { x: -1200, y: -880, z: 13 };
  const SETUP = { active: true, tool: 'hostess', tableId: null, sitting: false, keys: { place: 'E', menu: 'F7' } };
  const setupState = { layout: { version: 1, nextId: 1, furniture: false, waiters: [], tables: [] }, active: false, missing: [], busy: [], file: 'data/layout.json', saved: true, oneSync: true };
  const TOOL_ACTION = { hostess: 'hostess', waiter: 'waiter_add', seat: 'seat_add', spot: 'spot_add', manager: 'manager' };
  let spotCounter = 0;
  const here = (h) => { spotCounter += 1; return [B.x + (spotCounter % 6) * 1.4, B.y + Math.floor(spotCounter / 6) * 1.4, B.z, h || 0]; };
  function setupRefresh() {
    const L = setupState.layout;
    const missing = [];
    if (!L.hostess) missing.push('hostess');
    if (!L.waiters.length) missing.push('waiter');
    if (!L.tables.some((t) => t.seats.length)) missing.push('table');
    const was = setupState.active;
    setupState.missing = missing;
    setupState.active = missing.length === 0;
    return !was && setupState.active;
  }
  function setupPush() { dispatch('setup', Object.assign({}, SETUP, { setup: setupState })); }
  function setupDo(data) {
    const L = setupState.layout;
    const table = L.tables.find((t) => t.id === data.tableId);
    const needTable = ['table_remove', 'table_update', 'seat_add', 'seat_remove', 'seat_nudge', 'spot_add', 'spot_remove'];
    if (needTable.includes(data.action) && !table) return fail('setup_select_table', 'קודם בחרו שולחן בתפריט (או צרו שולחן חדש).');
    if (table && setupState.busy.includes(table.id) && data.action !== 'table_update') return fail('setup_table_busy', `לא ניתן לשנות כרגע: ${table.label} בשימוש (יושבים בו לקוחות או שהוא בניקיון). נסו שוב כשהוא פנוי.`);
    let message;
    switch (data.action) {
      case 'hostess': L.hostess = here(180); message = 'המארחת תעמוד כאן.'; break;
      case 'waiter_add': L.waiters.push(here(90)); message = `עמדת מלצר ${L.waiters.length} נוספה כאן.`; break;
      case 'waiter_remove': L.waiters.splice((data.index || L.waiters.length) - 1, 1); message = `עמדת מלצר ${data.index} נמחקה.`; break;
      case 'manager': L.manager = here().slice(0, 3); message = 'עמדת הניהול תהיה כאן.'; break;
      case 'manager_clear': delete L.manager; message = 'עמדת הניהול הוסרה.'; break;
      case 'table_add': {
        const id = L.nextId++;
        L.tables.push({ id, label: 'שולחן ' + id, vip: false, seatZ: 0, seats: [], spots: [] });
        SETUP.tableId = id;
        SETUP.tool = 'seat';
        message = `שולחן ${id} נוסף — עכשיו הציבו את הכיסאות שלו.`;
        break;
      }
      case 'table_remove': L.tables = L.tables.filter((t) => t !== table); SETUP.tableId = null; message = `${table.label} נמחק.`; break;
      case 'table_update':
        if (data.label !== undefined) table.label = String(data.label).slice(0, 24);
        if (data.vip !== undefined) table.vip = !!data.vip;
        if (data.seatZ !== undefined) table.seatZ = data.seatZ;
        message = `${table.label} עודכן.`;
        break;
      case 'seat_add': table.seats.push(here(0)); message = `כיסא ${table.seats.length} נוסף ל${table.label}.`; break;
      case 'seat_remove': table.seats.pop(); message = `הכיסא האחרון של ${table.label} נמחק.`; break;
      case 'seat_nudge': message = `כיסא ${data.index} של ${table.label} הוזז.`; break;
      case 'spot_add': table.spots.push(here()); message = `מקום לנרגילה ${table.spots.length} נוסף ל${table.label}.`; break;
      case 'spot_remove': table.spots.pop(); message = `מקום הנרגילה האחרון של ${table.label} נמחק.`; break;
      case 'furniture': L.furniture = !!data.enabled; message = L.furniture ? 'ייווצרו שולחנות וכיסאות בנקודות שהצבת.' : 'לא ייווצרו רהיטים — משתמשים ברהיטים של המפה.'; break;
      case 'reset':
        setupState.layout = { version: 1, nextId: 1, furniture: false, waiters: [], tables: [] };
        SETUP.tableId = null;
        message = 'ההצבה נמחקה — העסק חזר למיקומים שב-config.lua.';
        break;
      default: return fail('invalid_request', 'בקשה לא תקינה.');
    }
    if (setupRefresh()) message = `ההצבה הושלמה — ${D.business.name} פועל עכשיו כאן!`;
    setTimeout(setupPush, 10);
    return ok(Object.assign({}, setupState), message);
  }
  if (params.get('layout') === 'full') {
    const L = setupState.layout;
    L.hostess = here(180);
    L.waiters.push(here(90), here(270));
    L.manager = here().slice(0, 3);
    [['שולחן הספה', 4, 2, false, -0.1], ['שולחן החלון', 4, 2, false, 0], ['VIP השייח', 6, 3, true, 0], ['בר', 3, 0, false, 0.25]].forEach(([label, seats, spots, vip, seatZ]) => {
      const id = L.nextId++;
      L.tables.push({ id, label, vip, seatZ, seats: Array.from({ length: seats }, () => here(0)), spots: Array.from({ length: spots }, () => here()) });
    });
    setupState.busy = [2];
    SETUP.tool = 'seat';
    SETUP.tableId = 1;
  }
  setupRefresh();

  async function post(name, data) {
    data = data || {};
    await wait(name === 'pay' || name === 'placeOrder' ? 350 : 60);
    switch (name) {
      case 'ready':
        dispatch('init', { locale: D.locale, currency: D.currency, business: D.business, catalog: D.catalog, settings: D.settings, tables, me: me() });
        return ok();
      case 'close': case 'switchPanel': case 'contextClose': case 'copyDone': return ok();
      case 'contextSelect': return ok();
      case 'requestTable': {
        S.tableId = 3; S.seat = null; S.tableStatus = 'reserved';
        const t = tables.find((x) => x.id === 3); t.status = 'reserved';
        setTimeout(push, 10);
        return ok({ tableId: 3, label: t.label, holdFor: 180 }, fill(D.messages.table_assigned, { TABLE: t.label }));
      }
      case 'sit': seat(); setTimeout(push, 10); return ok();
      case 'leaveTable': {
        const unpaid = me().bill.personal;
        if (unpaid > 0) return fail('unpaid_bill_leave', `יש לך חשבון פתוח של ${money(unpaid)}. יש לשלם לפני העזיבה.`);
        S.tableId = null; S.seat = null; S.tableStatus = null; setTimeout(push, 10);
        return ok(null, 'עזבת את השולחן. תודה ולהתראות!');
      }
      case 'nearbyPlayers': return ok([{ id: 12, name: 'אור דוד' }, { id: 15, name: 'מיכל ברק' }]);
      case 'invite': return ok(null, 'שלחת הזמנה.');
      case 'placeOrder': {
        if (!Array.isArray(data.lines) || !data.lines.length) return fail('order_empty', 'ההזמנה ריקה.');
        const order = addOrder(data.lines, { note: data.note || null });
        progress(order);
        setTimeout(push, 10);
        return ok({ id: order.id, total: order.subtotal }, fill(D.messages.order_placed, { ID: order.id, TOTAL: money(order.subtotal) }));
      }
      case 'cancelOrder': {
        const order = S.orders.find((o) => o.id === data.orderId);
        if (!order || order.status !== 'new') return fail('order_cannot_cancel', 'אי אפשר לבטל את ההזמנה בשלב הזה.');
        order.status = 'cancelled'; order.paymentStatus = 'void'; setTimeout(push, 10);
        return ok();
      }
      case 'getBill': {
        const list = S.orders.filter((o) => o.paymentStatus === 'unpaid' && o.status !== 'cancelled' && (data.mode === 'table' || o.mine !== false));
        const subtotal = list.reduce((s, o) => s + o.subtotal, 0);
        return ok({
          mode: data.mode, tableLabel: me().tableLabel, moneyMode: 'money', canPayTable: true,
          servicePercent: D.settings.servicePercent, service: Math.round(subtotal * D.settings.servicePercent / 100),
          tips: D.settings.tips,
          accounts: D.settings.accounts.map((a) => Object.assign({}, a, { balance: a.id === 'cash' ? S.cash : S.bank })),
          orders: list.map(view), subtotal, empty: list.length === 0, token: 'preview-token-' + Date.now(),
        });
      }
      case 'pay': {
        const mode = data.token ? 'table' : 'personal';
        const list = S.orders.filter((o) => o.paymentStatus === 'unpaid' && o.status !== 'cancelled' && (mode === 'table' || o.mine !== false));
        const subtotal = list.reduce((s, o) => s + o.subtotal, 0);
        const tip = Math.round(subtotal * (data.tip || 0) / 100);
        const total = subtotal + tip;
        const key = data.account === 'cash' ? 'cash' : 'bank';
        if (S[key] < total) return fail('insufficient_funds', D.messages.insufficient_funds);
        S[key] -= total;
        list.forEach((o) => { o.paymentStatus = 'paid'; });
        setTimeout(push, 10);
        return ok({ total, subtotal, tip, service: 0, account: data.account }, fill(D.messages.payment_success, { TOTAL: money(total) }));
      }
      case 'consume': {
        const item = S.served.find((x) => x.id === data.itemId);
        if (!item) return fail('consume_none', 'הפריט הזה לא נמצא על השולחן שלך.');
        item.count -= 1;
        if (item.count <= 0) S.served = S.served.filter((x) => x !== item);
        setTimeout(push, 10);
        return ok();
      }
      case 'hookahAction': {
        const h = S.hookahs.find((x) => x.id === data.sessionId);
        if (!h) return fail('hookah_not_found', 'הנרגילה כבר לא זמינה.');
        if (data.action === 'end') S.hookahs = S.hookahs.filter((x) => x !== h);
        if (data.action === 'flavor') { h.flavors = data.flavors; h.flavorLabels = data.flavors.map((f) => flavors.get(f).label); }
        if (data.action === 'coals') { h.refreshes += 1; h.expires += 600000; }
        setTimeout(push, 10);
        return ok(null, data.action === 'use' ? null : 'בוצע.');
      }
      case 'callWaiter': return ok(null, 'המלצר קיבל את הקריאה.');
      case 'staffOpen': return ok(staff());
      case 'setupSelect':
        if (data.tool) SETUP.tool = data.tool;
        if (data.tableId !== undefined) SETUP.tableId = data.tableId || null;
        return ok();
      case 'setupPlace': {
        const action = TOOL_ACTION[SETUP.tool];
        if ((SETUP.tool === 'seat' || SETUP.tool === 'spot') && !SETUP.tableId) return fail('setup_select_table', 'קודם בחרו שולחן בתפריט (או צרו שולחן חדש).');
        return setupDo({ action, tableId: SETUP.tableId });
      }
      case 'setupAction':
        if (data.action === 'export') {
          if (!setupState.active) return fail('setup_export_incomplete', 'אפשר להעתיק קוד רק אחרי שההצבה הושלמה.');
          return ok({ text: 'Config.Tables = { -- ' + setupState.layout.tables.length + ' tables }' }, 'הקוד הועתק. אפשר להדביק אותו בסוף config.lua.');
        }
        return setupDo(data);
      case 'setupTestSit': SETUP.sitting = true; setTimeout(setupPush, 10); return ok();
      case 'setupExit': SETUP.active = false; setTimeout(setupPush, 10); return ok();
      case 'staffAction': {
        if (data.action === 'sales') {
          const days = [];
          for (let i = 6; i >= 0; i--) {
            const d = new Date(Date.now() - i * 86400000);
            days.push({ date: d.toISOString().slice(0, 10), revenue: [1840, 2310, 1290, 3120, 2680, 3990, 2240][6 - i], tips: 120, orders: 30, payments: 18 });
          }
          return ok({ today: { revenue: 2240, tips: 268, orders: 37, payments: 21 }, days, top: [
            { id: 'hookah_mix', label: 'נרגילת מיקס', qty: 14 }, { id: 'fries', label: 'צ\'יפס', qty: 11 },
            { id: 'beer_draft', label: 'בירה מהחבית', qty: 9 }, { id: 'tea_nana', label: 'תה נענע', qty: 8 }, { id: 'wings_bbq', label: 'כנפיים ברביקיו', qty: 6 },
          ], persisted: true });
        }
        if (data.action === 'logs') {
          const now = Math.floor(Date.now() / 1000);
          return ok([
            { time: now - 40, level: 'info', category: 'order', message: 'Order #43 by Shira [7] at שולחן 3: 57 ₪' },
            { time: now - 160, level: 'info', category: 'payment', message: 'Noam [1] paid 210 ₪ (בנק) for 2 order(s) [table]' },
            { time: now - 300, level: 'warn', category: 'security', message: 'Rate limit hit: placeOrder (Guest [22])' },
            { time: now - 640, level: 'info', category: 'table', message: 'שולחן 4: occupied → cleaning (empty)' },
          ]);
        }
        if (data.action === 'orderStatus') {
          const order = S.orders.find((o) => o.id === data.orderId);
          if (order) { order.status = data.status; if (data.status === 'completed') deliver(order); }
        }
        if (data.action === 'business') S.businessOpen = !!data.open;
        if (data.action === 'order') {
          if (!Array.isArray(data.lines) || !data.lines.length) return fail('order_empty', 'ההזמנה ריקה.');
          const order = addOrder(data.lines, { customer: 'אורח בשולחן', placedBy: 'דניאל (מלצר)', note: data.note || null });
          setTimeout(push, 10);
          return ok(null, `הזמנה #${order.id} נשלחה למטבח.`);
        }
        setTimeout(push, 10);
        return ok(null, 'עודכן.');
      }
      default:
        return fail('invalid_request', 'בקשה לא תקינה.');
    }
  }

  CCH.setPost(post);
  window.CCH_PREVIEW = { dispatch, post, state: S, me, staff, tables, setup: SETUP, setupState };

  post('ready').then(() => {
    const context = startPanel === 'bill' ? { mode: 'table' } : startPanel === 'setup' ? Object.assign({}, SETUP, { setup: setupState }) : {};
    dispatch('open', { panel: startPanel, context, me: me(), tables });
    if (startPanel === 'staff') dispatch('staff', staff());
  });
})();

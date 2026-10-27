/* Browser preview of the NUI (not loaded in game).
   Simulates the Lua side with the real catalog exported from config.lua
   (tests/nui/mock-data.js). Open html/index.html in a browser:
     index.html?panel=menu            (default)
     index.html?panel=host&scenario=new
     index.html?panel=orders | bill | staff
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
  const money = (n) => (D.currency.position === 'after' ? n + D.currency.symbol : D.currency.symbol + n);
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
      perms: ['view_tables', 'reserve_table', 'clean_table', 'seat_guest', 'release_table', 'view_orders', 'update_order', 'cancel_order', 'request_payment', 'view_sales', 'manage_stock', 'toggle_business', 'view_logs'],
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
    addOrder([{ id: 'edamame_spicy', qty: 1 }, { id: 'arak_grapefruit', qty: 1 }], { status: 'new', age: 25, customer: 'שירה לוי' });
  }

  const ok = (data, message) => ({ ok: true, data, message });
  const fail = (code, message) => ({ ok: false, code, message });

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
        const order = addOrder(data.lines);
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
            { time: now - 40, level: 'info', category: 'order', message: 'Order #43 by Shira [7] at שולחן 3: $57' },
            { time: now - 160, level: 'info', category: 'payment', message: 'Noam [1] paid $210 (בנק) for 2 order(s) [table]' },
            { time: now - 300, level: 'warn', category: 'security', message: 'Rate limit hit: placeOrder (Guest [22])' },
            { time: now - 640, level: 'info', category: 'table', message: 'שולחן 4: occupied → cleaning (empty)' },
          ]);
        }
        if (data.action === 'orderStatus') {
          const order = S.orders.find((o) => o.id === data.orderId);
          if (order) { order.status = data.status; if (data.status === 'completed') deliver(order); }
        }
        if (data.action === 'business') S.businessOpen = !!data.open;
        setTimeout(push, 10);
        return ok(null, 'עודכן.');
      }
      default:
        return fail('invalid_request', 'בקשה לא תקינה.');
    }
  }

  CCH.setPost(post);
  window.CCH_PREVIEW = { dispatch, post, state: S, me, staff, tables };

  post('ready').then(() => {
    dispatch('open', { panel: startPanel, context: startPanel === 'bill' ? { mode: 'table' } : {}, me: me(), tables });
    if (startPanel === 'staff') dispatch('staff', staff());
  });
})();

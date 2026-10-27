/* CypherCity Hookah Lounge — NUI application.
   Vanilla JS, no external libraries. The UI only displays data and sends ids and
   quantities; every price, permission and payment is decided by the server. */
(function () {
  'use strict';

  const IN_GAME = typeof window.GetParentResourceName === 'function';
  const RESOURCE = IN_GAME ? window.GetParentResourceName() : 'cyphercity-hookah';
  const ICON_PATH = 'assets/icons/';
  const IMAGE_RE = /^[\w.-]+\.(svg|png|webp|jpg)$/i;

  const S = {
    open: false,
    panel: 'menu',
    init: null,
    settings: {},
    catalog: { categories: [], products: [], flavors: [] },
    me: {},
    tables: [],
    staff: null,
    stateAt: Date.now(),
    cart: [],
    category: 'all',
    search: '',
    filters: new Set(),
    sort: 'recommended',
    orderAccount: null,
    party: 2,
    bill: null,
    billLoading: false,
    billMode: 'personal',
    tip: 0,
    billAccount: null,
    billResult: null,
    staffTab: 'orders',
    sales: null,
    logs: null,
    logCategory: null,
    modal: null,
    busy: new Set(),
    contextOpen: false,
  };

  let LOC = (window.CCH_LOCALES && window.CCH_LOCALES.he) || {};
  // Entrance animations play only when a panel / modal first appears, not on every re-render.
  let lastPanel = null;
  let lastModalKey = null;
  let products = new Map();
  let flavors = new Map();
  let categories = new Map();
  let post = realPost;

  const $ = (selector, root) => (root || document).querySelector(selector);
  const app = $('#app');
  const panelEl = $('#panel');
  const modalEl = $('#modal');

  // ── helpers ─────────────────────────────────────────────

  // Lua encodes an empty table as {} — every list coming from Lua goes through arr().
  function arr(value) {
    if (Array.isArray(value)) return value;
    if (value && typeof value === 'object') return Object.values(value);
    return [];
  }

  function normOrder(order) {
    order.lines = arr(order.lines).map((l) => Object.assign(l, { flavors: arr(l.flavors), flavorLabels: arr(l.flavorLabels) }));
    return order;
  }

  function normHookah(h) {
    h.flavors = arr(h.flavors);
    h.flavorLabels = arr(h.flavorLabels);
    return h;
  }

  function normMe(me) {
    me = me || {};
    me.orders = arr(me.orders).map(normOrder);
    me.served = arr(me.served);
    me.hookahs = arr(me.hookahs).map(normHookah);
    me.members = arr(me.members);
    me.invites = arr(me.invites);
    me.perms = arr(me.perms);
    me.bill = me.bill || {};
    return me;
  }

  function normTables(list) {
    return arr(list).map((t) => Object.assign(t, { occupiedSeats: arr(t.occupiedSeats) }));
  }

  function normStaff(staff) {
    if (!staff) return staff;
    staff.perms = arr(staff.perms);
    staff.orders = arr(staff.orders).map(normOrder);
    staff.tables = arr(staff.tables).map((t) => Object.assign(t, { members: arr(t.members) }));
    if (staff.stock) staff.stock = arr(staff.stock);
    return staff;
  }

  function normBill(bill) {
    if (!bill) return bill;
    bill.orders = arr(bill.orders).map(normOrder);
    bill.accounts = arr(bill.accounts);
    bill.tips = arr(bill.tips).map(Number);
    return bill;
  }

  function normCatalog(catalog) {
    catalog = catalog || {};
    return {
      categories: arr(catalog.categories),
      flavors: arr(catalog.flavors),
      products: arr(catalog.products).map((p) => Object.assign(p, {
        tags: arr(p.tags),
        allowedFlavors: p.allowedFlavors ? arr(p.allowedFlavors) : null,
      })),
    };
  }

  function t(key, vars) {
    let text = LOC[key];
    if (text === undefined) text = (window.CCH_LOCALES.he || {})[key];
    if (text === undefined) text = key;
    if (vars) {
      text = text.replace(/\{(\w+)\}/g, (m, name) => (vars[name] !== undefined ? vars[name] : m));
    }
    return text;
  }

  function esc(value) {
    return String(value === undefined || value === null ? '' : value)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  function moneyText(amount) {
    const currency = (S.init && S.init.currency) || { symbol: '$', position: 'before' };
    const n = Math.floor(Number(amount) || 0).toLocaleString('en-US');
    return currency.position === 'after' ? n + currency.symbol : currency.symbol + n;
  }

  function money(amount) {
    return `<span class="num">${esc(moneyText(amount))}</span>`;
  }

  function clock(seconds) {
    seconds = Math.max(0, Math.floor(seconds || 0));
    const m = Math.floor(seconds / 60);
    const s = seconds % 60;
    return `${m}:${String(s).padStart(2, '0')}`;
  }

  function ago(seconds) {
    seconds = Math.max(0, Math.floor(seconds || 0));
    return seconds < 60 ? t('seconds', { n: seconds }) : t('minutes', { n: Math.floor(seconds / 60) });
  }

  function icon(image) {
    const file = image && IMAGE_RE.test(image) ? image : 'platter.svg';
    return ICON_PATH + file;
  }

  function hasPerm(perm) {
    const list = (S.staff && S.staff.perms) || S.me.perms || [];
    return list.indexOf(perm) !== -1;
  }

  function requestId() {
    const bytes = new Uint8Array(12);
    (window.crypto || window.msCrypto).getRandomValues(bytes);
    return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
  }

  function svgIcon(name) {
    const paths = {
      success: '<path d="M5 12.5l4.2 4.2L19 7"/>',
      error: '<path d="M12 8v5M12 16.5v.01"/><circle cx="12" cy="12" r="9"/>',
      warning: '<path d="M12 4l9 16H3z"/><path d="M12 10v4M12 17v.01"/>',
      info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8v.01"/>',
      search: '<circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/>',
      clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
      check: '<path d="M5 12.5l4.2 4.2L19 7"/>',
    };
    return `<svg viewBox="0 0 24 24" aria-hidden="true">${paths[name] || ''}</svg>`;
  }

  async function realPost(name, data) {
    try {
      const response = await fetch(`https://${RESOURCE}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data || {}),
      });
      const text = await response.text();
      return text ? JSON.parse(text) : { ok: true };
    } catch (err) {
      return { ok: false, message: t('error_generic') };
    }
  }

  // Sends a request, tracks its busy state and shows the server's message.
  async function call(name, data, options) {
    const opts = options || {};
    const key = opts.busy || name;
    if (S.busy.has(key)) return { ok: false, busy: true };
    S.busy.add(key);
    if (opts.rerender !== false) render();
    let result;
    try {
      result = (await post(name, data)) || { ok: false };
    } finally {
      S.busy.delete(key);
    }
    if (!result.ok && result.message && !opts.silentError) toast(result.message, 'error');
    if (result.ok && result.message && opts.toastSuccess !== false) toast(result.message, 'success');
    if (opts.rerender !== false) render();
    return result;
  }

  function busy(key) {
    return S.busy.has(key);
  }

  function spinner() {
    return '<span class="spinner"></span>';
  }

  // ── catalog / cart ─────────────────────────────────────

  function indexCatalog() {
    products = new Map(S.catalog.products.map((p) => [p.id, p]));
    flavors = new Map(S.catalog.flavors.map((f) => [f.id, f]));
    categories = new Map(S.catalog.categories.map((c) => [c.id, c]));
  }

  function unitPrice(product, flavorIds) {
    let price = product.price;
    (flavorIds || []).forEach((id) => {
      const flavor = flavors.get(id);
      if (flavor) price += flavor.price;
    });
    return price;
  }

  function lineKey(id, flavorIds) {
    return id + '|' + (flavorIds || []).slice().sort().join(',');
  }

  function productQtyInCart(id) {
    return S.cart.filter((l) => l.id === id).reduce((sum, l) => sum + l.qty, 0);
  }

  function cartUnits() {
    return S.cart.reduce((sum, l) => sum + l.qty, 0);
  }

  function cartTotal() {
    return S.cart.reduce((sum, l) => {
      const product = products.get(l.id);
      return product ? sum + unitPrice(product, l.flavors) * l.qty : sum;
    }, 0);
  }

  function addToCart(id, flavorIds, qty) {
    const product = products.get(id);
    if (!product) return;
    qty = qty || 1;
    const maxItems = S.settings.maxItemsPerOrder || 25;
    if (productQtyInCart(id) + qty > (product.maxQty || 10) || cartUnits() + qty > maxItems) {
      toast(t('cart_max'), 'warning');
      return;
    }
    const key = lineKey(id, flavorIds);
    const existing = S.cart.find((l) => l.key === key);
    if (existing) existing.qty += qty;
    else S.cart.push({ key, id, qty, flavors: (flavorIds || []).slice() });
    render();
  }

  function changeQty(key, delta) {
    const line = S.cart.find((l) => l.key === key);
    if (!line) return;
    if (delta > 0) {
      const product = products.get(line.id);
      if (productQtyInCart(line.id) + delta > (product.maxQty || 10) || cartUnits() + delta > (S.settings.maxItemsPerOrder || 25)) {
        toast(t('cart_max'), 'warning');
        return;
      }
    }
    line.qty += delta;
    if (line.qty <= 0) S.cart = S.cart.filter((l) => l.key !== key);
    render();
  }

  function orderBlocker() {
    if (S.me.businessOpen === false) return 'menu_closed';
    if (!S.me.tableId && !S.settings.allowWithoutTable) return 'menu_need_table';
    if (S.me.tableId && S.me.tableStatus !== 'occupied') return 'menu_need_seat';
    return null;
  }

  // ── messages from Lua ───────────────────────────────────

  function onInit(data) {
    S.init = data;
    LOC = window.CCH_LOCALES[data.locale] || window.CCH_LOCALES.he;
    document.documentElement.lang = data.locale === 'en' ? 'en' : 'he';
    document.documentElement.dir = LOC.dir || 'rtl';
    S.settings = data.settings || {};
    S.settings.accounts = arr(S.settings.accounts);
    S.settings.tips = arr(S.settings.tips);
    S.catalog = normCatalog(data.catalog);
    S.tables = normTables(data.tables);
    S.me = normMe(data.me);
    S.stateAt = Date.now();
    indexCatalog();
    const accounts = S.settings.accounts || [];
    S.orderAccount = accounts.length ? accounts[0].id : null;
    S.billAccount = S.orderAccount;
    S.party = Math.min(2, S.settings.maxPartySize || 6);
    document.querySelectorAll('[data-t]').forEach((el) => { el.textContent = t(el.dataset.t); });
    document.querySelectorAll('[data-t-title]').forEach((el) => { el.title = t(el.dataset.tTitle); });
    if (S.open) render();
  }

  function onOpen(data) {
    data = data || {};
    if (data.me) { S.me = normMe(data.me); S.stateAt = Date.now(); }
    if (data.tables) S.tables = normTables(data.tables);
    const context = data.context || {};
    S.open = true;
    S.modal = null;
    app.hidden = false;
    let panel = data.panel || 'menu';
    if (panel === 'hookah') {
      panel = 'orders';
      const session = (S.me.hookahs || []).find((h) => h.id === context.sessionId);
      if (session) S.modal = { type: context.mode === 'coals' ? 'hookahCoals' : 'hookahFlavor', sessionId: session.id, selected: session.flavors.slice() };
    }
    if (panel === 'staff' && context.staff) S.staff = normStaff(context.staff);
    S.panel = panel;
    if (panel === 'bill') {
      S.billMode = context.mode || (S.me.isOwner && S.settings.allowTableBill ? 'table' : 'personal');
      loadBill();
    }
    render();
  }

  function hide() {
    S.open = false;
    S.modal = null;
    app.hidden = true;
    modalEl.hidden = true;
  }

  function close() {
    hide();
    post('close', {});
  }

  function handleMessage(message) {
    const data = message ? message.data : undefined;
    switch (message && message.action) {
      case 'init': onInit(data || {}); break;
      case 'open': onOpen(data); break;
      case 'close': hide(); break;
      case 'state':
        S.me = normMe(data);
        S.stateAt = Date.now();
        if (S.open) render();
        break;
      case 'tables':
        S.tables = normTables(data);
        if (S.open && (S.panel === 'host' || S.panel === 'staff')) render();
        break;
      case 'staff':
        S.staff = normStaff(data);
        if (S.open && S.panel === 'staff') render();
        break;
      case 'toast': toast(data.message, data.type, data.duration); break;
      case 'prompt': showPrompt(data || {}); break;
      case 'context': openContext(arr(data && data.options)); break;
      case 'clipboard': copyText(data && data.text); break;
      default: break;
    }
  }

  window.addEventListener('message', (event) => handleMessage(event.data));

  // ── rendering ───────────────────────────────────────────

  function tabs() {
    const list = ['host', 'menu', 'orders', 'bill'];
    if (S.me.staffRole) list.push('staff');
    const bill = S.me.bill || {};
    const ordersDot = (S.me.served || []).length > 0;
    const billDot = (bill.personal || 0) > 0;
    return list.map((p) => `
      <button class="tab ${S.panel === p ? 'active' : ''}" type="button" role="tab" data-action="tab" data-panel="${p}">
        ${esc(t('tab_' + p))}
        ${(p === 'orders' && ordersDot) || (p === 'bill' && billDot) ? '<i class="dot"></i>' : ''}
      </button>`).join('');
  }

  function render() {
    if (!S.open) return;
    const focused = document.activeElement;
    const focusId = focused && focused.id;
    const caret = focused && typeof focused.selectionStart === 'number' ? focused.selectionStart : null;

    $('#tabs').innerHTML = tabs();
    const badge = $('#tableBadge');
    badge.textContent = S.me.tableLabel ? t('table_badge', { table: S.me.tableLabel }) : t('no_table_badge');
    badge.classList.toggle('muted', !S.me.tableLabel);

    const renderers = { host: renderHost, menu: renderMenu, orders: renderOrders, bill: renderBill, staff: renderStaff };
    const panelKey = S.panel + ':' + (S.panel === 'staff' ? S.staffTab : S.panel === 'menu' ? S.category : '');
    const fresh = panelKey !== lastPanel;
    lastPanel = panelKey;
    const scroller = panelEl.querySelector('.product-grid, .orders-layout, .staff-body, .host-layout, .bill-layout');
    const scrollTop = !fresh && scroller ? scroller.scrollTop : 0;
    panelEl.innerHTML = `<div class="panel ${fresh ? '' : 'static'}">${(renderers[S.panel] || renderMenu)()}</div>`;
    if (scrollTop) {
      const next = panelEl.querySelector('.product-grid, .orders-layout, .staff-body, .host-layout, .bill-layout');
      if (next) next.scrollTop = scrollTop;
    }
    renderModal();

    if (focusId) {
      const el = document.getElementById(focusId);
      if (el) {
        el.focus();
        if (caret !== null && typeof el.setSelectionRange === 'function') el.setSelectionRange(caret, caret);
      }
    }
    tickTimers();
  }

  // Host ----------------------------------------------------------------------

  function renderHost() {
    const me = S.me;
    const business = (S.init && S.init.business) || {};
    const maxParty = S.settings.maxPartySize || 6;
    let left;
    if (me.tableId) {
      left = renderMyTable();
    } else if (me.businessOpen === false) {
      left = `<div class="notice warn">${esc(t('host_closed'))}</div>`;
    } else {
      const buttons = [];
      for (let i = 1; i <= maxParty; i++) {
        buttons.push(`<button type="button" class="${S.party === i ? 'active' : ''}" data-action="party" data-n="${i}">${i}</button>`);
      }
      left = `
        <div class="muted small">${esc(t('host_party'))}</div>
        <div class="party">${buttons.join('')}</div>
        <button class="btn gold lg" type="button" data-action="requestTable" ${busy('requestTable') ? 'disabled' : ''}>
          ${busy('requestTable') ? spinner() + esc(t('host_requesting')) : esc(t('host_request'))}
        </button>`;
    }

    const invites = (me.invites || []).length && !me.tableId ? `
      <div class="card">
        <h3 class="h-section">${esc(t('host_invites'))}</h3>
        <div class="member-list">
          ${me.invites.map((inv) => `
            <div class="row" style="display:flex;justify-content:space-between;align-items:center;gap:.6rem">
              <span>${esc(t('host_invite_from', { from: inv.from || '', table: inv.label }))}</span>
              <button class="btn sm outline-gold" type="button" data-action="sit" data-table="${inv.tableId}">${esc(t('host_go_sit'))}</button>
            </div>`).join('')}
        </div>
      </div>` : '';

    return `
      <div class="host-layout">
        <div class="host-welcome">
          <div class="host-hero">
            <img class="hero-icon" src="${ICON_PATH}hookah.svg" alt="">
            <h2 class="h-display">${esc(t('host_greeting', { name: business.hostess || '' }))}</h2>
            ${me.tableId ? '' : `<p>${esc(t('host_question'))}</p>`}
            <div style="margin-top:1rem">${left}</div>
          </div>
          ${invites}
        </div>
        <div>
          <h3 class="h-section">${esc(t('host_floor'))}</h3>
          <div class="floor">${S.tables.map(renderFloorTable).join('')}</div>
          <div class="legend">
            ${['free', 'reserved', 'occupied', 'cleaning'].map((s) => `<span class="status ${s}">${esc(t('status_' + s))}</span>`).join('')}
          </div>
        </div>
      </div>`;
  }

  function renderFloorTable(table) {
    const mine = S.me.tableId === table.id;
    const dots = (table.occupiedSeats || []).slice(0, table.capacity).map((on) => `<i class="${on ? 'on' : ''}"></i>`).join('');
    return `
      <div class="floor-table status-${esc(table.status)} ${mine ? 'mine' : ''}">
        <div class="ft-head">
          <span class="ft-name">${esc(table.label)}</span>
          ${table.vip ? `<span class="vip-mark">${esc(t('vip'))}</span>` : ''}
        </div>
        <span class="status ${esc(table.status)}">${esc(t('status_' + table.status))}</span>
        <div class="seat-dots">${dots}</div>
        <span class="faint small">${esc(t('seats', { n: table.capacity }))}</span>
      </div>`;
  }

  function renderMyTable() {
    const me = S.me;
    const seated = me.seat !== undefined && me.seat !== null;
    const holdLeft = me.reservedFor ? Math.max(0, me.reservedFor - Math.floor((Date.now() - S.stateAt) / 1000)) : 0;
    const members = (me.members || []).map((m) => `
      <li>
        <span>${esc(m.name)} ${m.owner ? `<span class="tag popular">${esc(t('host_owner'))}</span>` : ''}</span>
        <span class="faint small">${esc(m.seated ? t('host_seated') : t('host_standing'))}</span>
      </li>`).join('');
    return `
      <div class="my-table">
        <div class="row">
          <div>
            <div class="muted small">${esc(t('host_your_table'))}</div>
            <div class="table-name">${esc(me.tableLabel)}</div>
          </div>
          <span class="status ${esc(me.tableStatus)}">${esc(t('status_' + me.tableStatus))}</span>
        </div>
        ${me.tableStatus === 'reserved' && holdLeft ? `<div class="notice warn">${esc(t('host_hold'))} <b class="num" data-countdown="${Date.now() + holdLeft * 1000}">${clock(holdLeft)}</b></div>` : ''}
        <div>
          <div class="muted small" style="margin-bottom:.4rem">${esc(t('host_members'))}</div>
          <ul class="member-list">${members}</ul>
        </div>
        <div class="actions">
          ${seated ? '' : `<button class="btn gold" type="button" data-action="sit" data-table="${me.tableId}">${esc(t('host_go_sit'))}</button>`}
          <button class="btn outline-gold" type="button" data-action="tab" data-panel="menu">${esc(t('host_open_menu'))}</button>
          ${me.isOwner ? `<button class="btn" type="button" data-action="openInvite">${esc(t('host_invite'))}</button>` : ''}
          <button class="btn danger" type="button" data-action="leaveTable" ${busy('leaveTable') ? 'disabled' : ''}>${esc(t('host_leave'))}</button>
        </div>
      </div>`;
  }

  // Menu ----------------------------------------------------------------------

  function visibleProducts() {
    const query = S.search.trim().toLowerCase();
    let list = S.catalog.products.filter((p) => {
      if (S.category !== 'all' && p.category !== S.category) return false;
      if (query && !(p.label.toLowerCase().includes(query) || (p.description || '').toLowerCase().includes(query))) return false;
      for (const tag of S.filters) {
        if (!(p.tags || []).includes(tag)) return false;
      }
      return true;
    });
    if (S.sort === 'price_asc') list = list.slice().sort((a, b) => a.price - b.price);
    else if (S.sort === 'price_desc') list = list.slice().sort((a, b) => b.price - a.price);
    else if (S.sort === 'name') list = list.slice().sort((a, b) => a.label.localeCompare(b.label, 'he'));
    else {
      list = list.slice().sort((a, b) => {
        const pa = (a.tags || []).includes('popular') ? 0 : 1;
        const pb = (b.tags || []).includes('popular') ? 0 : 1;
        return pa - pb;
      });
    }
    return list;
  }

  function renderMenu() {
    const counts = {};
    S.catalog.products.forEach((p) => { counts[p.category] = (counts[p.category] || 0) + 1; });
    const cats = [`
      <button class="category ${S.category === 'all' ? 'active' : ''}" type="button" data-action="category" data-id="all">
        <img src="${ICON_PATH}logo.svg" alt=""><span>${esc(t('menu_all'))}</span><span class="count">${S.catalog.products.length}</span>
      </button>`].concat(S.catalog.categories.map((c) => `
      <button class="category ${S.category === c.id ? 'active' : ''}" type="button" data-action="category" data-id="${esc(c.id)}">
        <img src="${icon(c.icon)}" alt=""><span>${esc(c.label)}</span><span class="count">${counts[c.id] || 0}</span>
      </button>`)).join('');

    const tagSet = new Set();
    S.catalog.products.forEach((p) => (p.tags || []).forEach((tag) => tagSet.add(tag)));
    const filterChips = Array.from(tagSet).filter((tag) => LOC['tag_' + tag]).map((tag) => `
      <button class="chip ${S.filters.has(tag) ? 'active' : ''}" type="button" data-action="filter" data-tag="${esc(tag)}">${esc(t('tag_' + tag))}</button>`).join('');

    const list = visibleProducts();
    const blocker = orderBlocker();
    const cards = list.length ? list.map(renderProduct).join('') : `<div class="empty" style="grid-column:1/-1"><img src="${ICON_PATH}logo.svg" alt=""><span>${esc(t('menu_empty'))}</span></div>`;

    return `
      <div class="menu-layout">
        <aside class="categories">${cats}</aside>
        <section class="products">
          <div class="toolbar">
            <label class="search">${svgIcon('search')}<input class="input" id="menuSearch" type="text" autocomplete="off" placeholder="${esc(t('menu_search'))}" value="${esc(S.search)}"></label>
            <select class="input" id="menuSort">
              ${['recommended', 'price_asc', 'price_desc', 'name'].map((s) => `<option value="${s}" ${S.sort === s ? 'selected' : ''}>${esc(t('menu_sort_' + s))}</option>`).join('')}
            </select>
            <div class="filters">${filterChips}</div>
          </div>
          ${blocker ? `<div style="padding:.8rem 1.2rem 0"><div class="notice warn">${esc(t(blocker))}</div></div>` : ''}
          <div class="product-grid">${cards}</div>
        </section>
        ${renderCart(blocker)}
      </div>`;
  }

  function renderProduct(p, index) {
    const qty = productQtyInCart(p.id);
    const prep = p.prepTime ? (p.prepTime >= 60 ? t('menu_prep', { n: Math.round(p.prepTime / 60) }) : t('menu_prep_sec', { n: p.prepTime })) : '';
    const tags = (p.tags || []).filter((tag) => LOC['tag_' + tag]).map((tag) => `<span class="tag ${esc(tag)}">${esc(t('tag_' + tag))}</span>`).join('');
    const isHookah = p.kind === 'hookah';
    return `
      <article class="product" style="animation-delay:${Math.min(index, 12) * 25}ms">
        ${qty ? `<span class="in-cart">${qty}</span>` : ''}
        <div class="art"><img src="${icon(p.image)}" alt=""></div>
        <div class="body">
          <div class="name">${esc(p.label)}</div>
          <div class="desc">${esc(p.description)}</div>
          <div class="meta">
            ${tags}
            ${prep ? `<span class="prep">${svgIcon('clock').replace('<svg', '<svg style="width:.8rem;height:.8rem;stroke:currentColor;fill:none;stroke-width:2"')}${esc(prep)}</span>` : ''}
            ${isHookah && p.duration ? `<span class="prep">${esc(t('menu_duration', { n: Math.round(p.duration / 60) }))}</span>` : ''}
          </div>
          <div class="foot">
            <span class="price">${isHookah ? `<small>${esc(t('menu_from'))}</small> ` : ''}${money(p.price)}</span>
            <button class="add-btn" type="button" data-action="add" data-id="${esc(p.id)}">${esc(isHookah ? t('menu_choose_flavor') : '+ ' + t('menu_add'))}</button>
          </div>
        </div>
      </article>`;
  }

  function renderCart(blocker) {
    const lines = S.cart.map((line) => {
      const p = products.get(line.id);
      if (!p) return '';
      const unit = unitPrice(p, line.flavors);
      const flavorText = line.flavors.length ? line.flavors.map((id) => (flavors.get(id) || {}).label || id).join(' + ') : '';
      return `
        <div class="cart-line">
          <span class="ln-name">${esc(p.label)}</span>
          <span class="ln-total">${money(unit * line.qty)}</span>
          ${flavorText ? `<span class="ln-sub">${esc(flavorText)}</span>` : ''}
          <div class="ln-controls">
            <span class="stepper">
              <button type="button" data-action="qty" data-key="${esc(line.key)}" data-delta="1">+</button>
              <span>${line.qty}</span>
              <button type="button" data-action="qty" data-key="${esc(line.key)}" data-delta="-1">−</button>
            </span>
            <span class="faint small">${money(unit)} ${esc(t('cart_unit'))}</span>
            <button class="link-btn" type="button" data-action="removeLine" data-key="${esc(line.key)}">${esc(t('cart_remove'))}</button>
          </div>
        </div>`;
    }).join('');

    const accounts = S.settings.accounts || [];
    const payNow = S.settings.timing === 'on_order' && S.settings.moneyMode === 'money';
    const sending = busy('placeOrder');
    return `
      <aside class="cart">
        <div class="cart-head">
          <h3>${esc(t('cart_title'))}</h3>
          ${S.cart.length ? `<button class="link-btn" type="button" data-action="clearCart">${esc(t('cart_clear'))}</button>` : ''}
        </div>
        <div class="cart-lines">
          ${lines || `<div class="empty"><img src="${ICON_PATH}hookah.svg" alt=""><span class="small">${esc(t('cart_empty'))}</span></div>`}
        </div>
        <div class="cart-foot">
          ${payNow ? `
            <div class="muted small">${esc(t('cart_account'))}</div>
            <div class="option-grid">
              ${accounts.map((a) => `<button type="button" class="option ${S.orderAccount === a.id ? 'active' : ''}" data-action="orderAccount" data-id="${esc(a.id)}">${esc(a.label)}</button>`).join('')}
            </div>
            <div class="faint small">${esc(t('cart_pay_now'))}</div>` : ''}
          <div class="total-row"><span class="muted">${esc(t('cart_subtotal'))}</span><span class="total">${money(cartTotal())}</span></div>
          <div class="faint small">${esc(t('cart_note'))}</div>
          <button class="btn gold block lg" type="button" data-action="placeOrder" ${!S.cart.length || blocker || sending ? 'disabled' : ''}>
            ${sending ? spinner() + esc(t('cart_sending')) : esc(t('cart_send'))}
          </button>
        </div>
      </aside>`;
  }

  // Orders --------------------------------------------------------------------

  const FLOW = ['new', 'preparing', 'serving', 'completed'];

  function renderProgress(status) {
    if (status === 'cancelled') return '';
    const index = FLOW.indexOf(status);
    return `<div class="progress">${FLOW.map((s, i) => `
      <div class="step ${i < index || status === 'completed' ? 'done' : ''} ${i === index && status !== 'completed' ? 'current' : ''}">
        <div class="bar"></div><span>${esc(t('order_' + s))}</span>
      </div>`).join('')}</div>`;
  }

  function payStatus(order) {
    const key = order.free && order.paymentStatus === 'paid' ? 'free' : order.paymentStatus;
    return `<span class="status ${esc(order.paymentStatus)}">${esc(t('pay_' + key))}</span>`;
  }

  function renderOrderLines(lines) {
    return (lines || []).map((l) => `
      <li><span>${esc(l.label)} × ${l.qty}${l.flavorLabels && l.flavorLabels.length ? ` <span class="faint small">(${esc(l.flavorLabels.join(' + '))})</span>` : ''}</span><span>${money(l.total)}</span></li>`).join('');
  }

  function renderOrders() {
    const orders = S.me.orders || [];
    const elapsed = Math.floor((Date.now() - S.stateAt) / 1000);
    const list = orders.length ? orders.map((o) => `
      <article class="card order-card">
        <div class="oc-head">
          <div>
            <span class="oc-id">#${String(o.id).padStart(3, '0')}</span>
            <span class="faint small">· ${esc(t('orders_ago', { t: ago(o.age + elapsed) }))}</span>
          </div>
          ${o.mine ? `<span class="tag popular">${esc(t('orders_mine'))}</span>` : `<span class="faint small">${esc(t('orders_by', { name: o.customer }))}</span>`}
          <span class="status ${esc(o.status)}">${esc(t('order_' + o.status))}</span>
        </div>
        ${o.kind === 'order' ? renderProgress(o.status) : ''}
        <ul class="oc-lines">${renderOrderLines(o.lines)}</ul>
        <div class="oc-foot">
          <span><b class="gold">${money(o.subtotal)}</b> ${payStatus(o)}</span>
          ${o.eta && o.status === 'preparing' ? `<span class="faint small">${esc(t('orders_eta', { t: ago(Math.max(0, o.eta - elapsed)) }))}</span>` : ''}
          ${o.mine && o.status === 'new' && o.kind === 'order' ? `<button class="btn sm danger" type="button" data-action="cancelOrder" data-id="${o.id}">${esc(t('orders_cancel'))}</button>` : ''}
        </div>
      </article>`).join('') : `<div class="empty"><img src="${ICON_PATH}platter.svg" alt=""><span>${esc(t('orders_empty'))}</span>
        <button class="btn outline-gold" type="button" data-action="tab" data-panel="menu">${esc(t('tab_menu'))}</button></div>`;

    const served = (S.me.served || []).map((item) => `
      <div class="served-item">
        <img src="${icon(item.image)}" alt="">
        <span class="si-name">${esc(item.label)}</span>
        <span class="si-count">× ${item.count}</span>
        <button class="btn sm outline-gold" type="button" data-action="consume" data-id="${esc(item.id)}" ${busy('consume') ? 'disabled' : ''}>${esc(t('served_consume'))}</button>
      </div>`).join('');

    const myId = S.me.serverId;
    const hookahs = (S.me.hookahs || []).map((h) => {
      const until = Date.now() + h.remaining * 1000 - elapsed * 1000;
      const pct = Math.max(0, Math.min(100, ((h.remaining - elapsed) / h.total) * 100));
      const inUse = h.activeUser !== undefined && h.activeUser !== null && h.activeUser !== myId;
      const canEnd = S.me.isOwner || h.owner === myId;
      return `
        <div class="hookah-card">
          <div class="hk-head">
            <span class="hk-name">${esc(h.label)}</span>
            <span class="status ${inUse ? 'preparing' : 'free'}">${esc(t(inUse ? 'hookah_in_use' : 'hookah_free'))}</span>
          </div>
          <div class="hk-flavors">${(h.flavors || []).map((id, i) => `<span class="flavor-dot" style="--c:${esc((flavors.get(id) || {}).color || '#c9a45c')}">${esc((h.flavorLabels || [])[i] || id)}</span>`).join('')}</div>
          <div class="timer"><i data-bar-until="${until}" data-bar-total="${h.total}" style="width:${pct}%"></i></div>
          <div class="faint small" data-countdown="${until}" data-countdown-format="hookah_left">${esc(t('hookah_left', { t: clock(h.remaining - elapsed) }))}</div>
          <div class="actions">
            <button class="btn sm gold" type="button" data-action="hookahUse" data-id="${h.id}" ${inUse || !S.me.seat ? 'disabled' : ''}>${esc(t('hookah_smoke'))}</button>
            ${S.settings.flavorChange && S.settings.flavorChange.enabled ? `<button class="btn sm" type="button" data-action="hookahFlavor" data-id="${h.id}">${esc(t('hookah_flavor'))}</button>` : ''}
            ${S.settings.coalRefresh && S.settings.coalRefresh.enabled ? `<button class="btn sm" type="button" data-action="hookahCoals" data-id="${h.id}">${esc(t('hookah_coals'))}</button>` : ''}
            ${canEnd ? `<button class="btn sm danger" type="button" data-action="hookahEnd" data-id="${h.id}">${esc(t('hookah_end'))}</button>` : ''}
          </div>
        </div>`;
    }).join('');

    return `
      <div class="orders-layout">
        <section>
          <h3 class="h-section">${esc(t('orders_title'))}</h3>
          ${list}
        </section>
        <section>
          <h3 class="h-section">${esc(t('hookahs_title'))}</h3>
          <div class="hookah-list">${hookahs || `<div class="faint small">${esc(t('hookahs_empty'))}</div>`}</div>
          <h3 class="h-section" style="margin-top:1.4rem">${esc(t('served_title'))}</h3>
          <div class="served-list">${served || `<div class="faint small">${esc(t('served_empty'))}</div>`}</div>
        </section>
      </div>`;
  }

  // Bill ----------------------------------------------------------------------

  async function loadBill() {
    S.bill = null;
    S.billResult = null;
    S.billLoading = true;
    render();
    const result = await call('getBill', { mode: S.billMode }, { rerender: false, toastSuccess: false });
    S.billLoading = false;
    if (result.ok) {
      S.bill = normBill(result.data);
      if (S.bill && S.bill.tips && S.bill.tips.indexOf(S.tip) === -1) S.tip = S.bill.tips[0] || 0;
      if (S.bill && S.bill.accounts && !S.bill.accounts.find((a) => a.id === S.billAccount)) {
        S.billAccount = S.bill.accounts.length ? S.bill.accounts[0].id : null;
      }
    }
    render();
  }

  function billTotals(bill) {
    const tip = Math.round((bill.subtotal * S.tip) / 100);
    return { tip, total: bill.subtotal + bill.service + tip };
  }

  function renderBill() {
    if (S.billResult) {
      const r = S.billResult;
      return `
        <div class="bill-layout" style="grid-template-columns:1fr">
          <div class="paid-state">
            <div class="check">${svgIcon('check')}</div>
            <h2 class="h-display">${esc(t('bill_paid_title'))}</h2>
            <p class="muted">${r.free ? esc(t('bill_free_notice')) : t('bill_paid_text', { amount: money(r.total) })}</p>
            <button class="btn outline-gold" type="button" data-action="close">${esc(t('close'))}</button>
          </div>
        </div>`;
    }
    if (S.billLoading || !S.bill) {
      return `<div class="empty" style="height:100%">${spinner()}<span>${esc(t('loading'))}</span></div>`;
    }
    const bill = S.bill;
    const modeSeg = bill.canPayTable ? `
      <div class="seg">
        <button type="button" class="${S.billMode === 'personal' ? 'active' : ''}" data-action="billMode" data-mode="personal">${esc(t('bill_personal'))}</button>
        <button type="button" class="${S.billMode === 'table' ? 'active' : ''}" data-action="billMode" data-mode="table">${esc(t('bill_table'))}</button>
      </div>` : '';
    if (bill.empty) {
      return `<div class="bill-layout" style="grid-template-columns:1fr"><div class="empty"><img src="${ICON_PATH}logo.svg" alt="">${modeSeg}<span>${esc(t('bill_empty'))}</span></div></div>`;
    }
    const totals = billTotals(bill);
    const groups = bill.orders.map((o) => `
      <div class="receipt-group">
        <div class="rg-head"><span>${esc(t('bill_order', { id: String(o.id).padStart(3, '0') }))}</span><span>${esc(o.customer || '')}</span></div>
        ${(o.lines || []).map((l) => `
          <div class="receipt-line">
            <span>${esc(l.label)} × ${l.qty}${l.flavorLabels && l.flavorLabels.length ? ` <span class="sub">${esc(l.flavorLabels.join(' + '))}</span>` : ''}</span>
            <span class="leader"></span>
            <span>${money(l.total)}</span>
          </div>`).join('')}
      </div>`).join('');

    const tips = (bill.tips || [0]).map((p) => `
      <button type="button" class="option ${S.tip === p ? 'active' : ''}" data-action="tip" data-p="${p}">
        ${p ? `<span class="num">${p}%</span>` : esc(t('bill_no_tip'))}
        ${p ? `<span class="o-sub">${money(Math.round((bill.subtotal * p) / 100))}</span>` : ''}
      </button>`).join('');

    const accounts = bill.moneyMode === 'money' ? `
      <div>
        <div class="muted small" style="margin-bottom:.4rem">${esc(t('bill_account'))}</div>
        <div class="option-grid">
          ${bill.accounts.map((a) => `
            <button type="button" class="option ${S.billAccount === a.id ? 'active' : ''}" data-action="billAccount" data-id="${esc(a.id)}">
              ${esc(a.label)}
              ${typeof a.balance === 'number' ? `<span class="o-sub">${t('bill_balance', { amount: money(a.balance) })}</span>` : ''}
            </button>`).join('')}
        </div>
      </div>` : '';

    const paying = busy('pay');
    return `
      <div class="bill-layout">
        <div class="receipt">
          <div class="receipt-head">
            <img src="${ICON_PATH}logo.svg" alt="">
            <div class="r-title">CYPHERCITY</div>
            <div class="faint small">${esc(bill.tableLabel || '')}</div>
          </div>
          ${groups}
          <div class="receipt-sum">
            <div class="total-row"><span class="muted">${esc(t('bill_subtotal'))}</span><span>${money(bill.subtotal)}</span></div>
            ${bill.service ? `<div class="total-row"><span class="muted">${t('bill_service', { p: `<span class="num">${Number(bill.servicePercent)}%</span>` })}</span><span>${money(bill.service)}</span></div>` : ''}
            ${totals.tip ? `<div class="total-row"><span class="muted">${esc(t('bill_tip'))} (<span class="num">${S.tip}%</span>)</span><span>${money(totals.tip)}</span></div>` : ''}
            <div class="total-row"><span>${esc(t('bill_total'))}</span><span class="grand">${money(totals.total)}</span></div>
          </div>
        </div>
        <div class="pay-side">
          <div style="display:flex;justify-content:space-between;align-items:center;gap:.6rem">
            ${modeSeg || '<span></span>'}
            <button class="btn sm ghost" type="button" data-action="reloadBill">${esc(t('bill_refresh'))}</button>
          </div>
          ${bill.tips && bill.tips.length > 1 ? `<div><div class="muted small" style="margin-bottom:.4rem">${esc(t('bill_tip'))}</div><div class="option-grid">${tips}</div></div>` : ''}
          ${accounts}
          ${bill.moneyMode === 'free' ? `<div class="notice">${esc(t('bill_free_notice'))}</div>` : ''}
          <button class="btn gold lg block" type="button" data-action="confirmPay" ${paying ? 'disabled' : ''}>
            ${paying ? spinner() + esc(t('bill_paying')) : t('bill_pay', { amount: money(totals.total) })}
          </button>
          <div class="faint small">${esc(t('cart_note'))}</div>
        </div>
      </div>`;
  }

  // Staff ---------------------------------------------------------------------

  function staffTabs() {
    const list = ['orders', 'tables'];
    if (hasPerm('view_sales')) list.push('sales');
    if (S.staff && S.staff.stock) list.push('stock');
    if (hasPerm('view_logs')) list.push('logs');
    if (hasPerm('toggle_business')) list.push('business');
    if (list.indexOf(S.staffTab) === -1) S.staffTab = list[0];
    return list;
  }

  function renderStaff() {
    if (!S.staff) {
      return `<div class="empty" style="height:100%">${spinner()}<span>${esc(t('loading'))}</span></div>`;
    }
    const list = staffTabs();
    const bodies = { orders: staffOrders, tables: staffTables, sales: staffSales, stock: staffStock, logs: staffLogs, business: staffBusiness };
    return `
      <div class="staff-layout">
        <div class="staff-top">
          <div class="subtabs">
            ${list.map((tab) => `<button class="chip ${S.staffTab === tab ? 'active' : ''}" type="button" data-action="staffTab" data-tab="${tab}">${esc(t('staff_' + tab))}</button>`).join('')}
          </div>
          <div style="display:flex;gap:.5rem;align-items:center">
            <span class="status ${S.staff.businessOpen ? 'free' : 'cancelled'}">${esc(t(S.staff.businessOpen ? 'staff_business_open' : 'staff_business_closed'))}</span>
            <span class="badge">${esc(t('staff_role', { role: t('role_' + S.staff.role) }))}</span>
          </div>
        </div>
        <div class="staff-body">${(bodies[S.staffTab] || staffOrders)()}</div>
      </div>`;
  }

  function ticket(o, actions) {
    const late = o.age > 600 && o.status !== 'completed';
    return `
      <div class="ticket ${late ? 'late' : ''}">
        <div class="t-head">
          <span class="t-id">#${String(o.id).padStart(3, '0')}</span>
          <span class="faint small">${esc(o.tableLabel || '-')} · ${esc(ago(o.age))}</span>
        </div>
        <div class="small">${esc(o.customer || '')}</div>
        <ul>${(o.lines || []).map((l) => `<li>${esc(l.label)} × ${l.qty}${l.flavorLabels && l.flavorLabels.length ? ` (${esc(l.flavorLabels.join(' + '))})` : ''}</li>`).join('')}</ul>
        <div class="faint small">${o.auto ? esc(t('staff_kitchen')) : o.handler ? esc(t('staff_handler', { name: o.handler })) : ''}</div>
        <div class="t-head"><b class="gold">${money(o.subtotal)}</b>${payStatus(o)}</div>
        <div class="t-actions">${actions}</div>
      </div>`;
  }

  function staffOrders() {
    const orders = S.staff.orders || [];
    const canUpdate = hasPerm('update_order');
    const canCancel = hasPerm('cancel_order');
    const next = { new: ['preparing', 'staff_accept'], preparing: ['serving', 'staff_ready'], serving: ['completed', 'staff_served'] };
    const col = (status) => {
      const items = orders.filter((o) => o.status === status && o.kind === 'order');
      return `
        <div class="kanban-col">
          <h4><span>${esc(t('staff_col_' + status))}</span><span class="faint">${items.length}</span></h4>
          ${items.map((o) => ticket(o, `
            ${canUpdate ? `<button class="btn sm gold" type="button" data-action="staffOrder" data-id="${o.id}" data-status="${next[status][0]}">${esc(t(next[status][1]))}</button>` : ''}
            ${canCancel ? `<button class="btn sm danger" type="button" data-action="staffCancel" data-id="${o.id}">${esc(t('staff_cancel'))}</button>` : ''}
          `)).join('') || `<div class="faint small">—</div>`}
        </div>`;
    };
    const unpaid = orders.filter((o) => o.paymentStatus === 'unpaid' && (o.status === 'completed'));
    return `
      <div class="kanban">${col('new')}${col('preparing')}${col('serving')}</div>
      ${unpaid.length ? `
        <div class="unpaid-strip">
          <h3 class="h-section">${esc(t('staff_col_unpaid'))}</h3>
          <div class="kanban">${unpaid.map((o) => ticket(o, canCancel ? `<button class="btn sm danger" type="button" data-action="staffCancel" data-id="${o.id}">${esc(t('staff_void'))}</button>` : '')).join('')}</div>
        </div>` : ''}
      ${!orders.length ? `<div class="empty">${esc(t('staff_no_orders'))}</div>` : ''}`;
  }

  function staffTables() {
    const rows = (S.staff.tables || []).map((tb) => {
      const actions = [];
      if (tb.status === 'cleaning' && hasPerm('clean_table')) actions.push(`<button class="btn sm success" type="button" data-action="staffTable" data-id="${tb.id}" data-op="clean">${esc(t('staff_clean'))}</button>`);
      if (tb.status === 'free' && hasPerm('reserve_table')) actions.push(`<button class="btn sm" type="button" data-action="staffReserve" data-id="${tb.id}">${esc(t('staff_reserve'))}</button>`);
      if (tb.status === 'reserved' && !tb.owner && hasPerm('reserve_table')) actions.push(`<button class="btn sm" type="button" data-action="staffTable" data-id="${tb.id}" data-op="unreserve">${esc(t('staff_unreserve'))}</button>`);
      if ((tb.status === 'free' || (tb.status === 'reserved' && !tb.owner)) && hasPerm('seat_guest')) actions.push(`<button class="btn sm outline-gold" type="button" data-action="staffSeat" data-id="${tb.id}">${esc(t('staff_seat_guest'))}</button>`);
      if (tb.unpaid > 0 && tb.owner && hasPerm('request_payment')) actions.push(`<button class="btn sm outline-gold" type="button" data-action="staffRequestPay" data-id="${tb.id}">${esc(t('staff_request_payment'))}</button>`);
      if (tb.status !== 'free' && hasPerm('release_table')) actions.push(`<button class="btn sm danger" type="button" data-action="staffRelease" data-id="${tb.id}" data-label="${esc(tb.label)}">${esc(t('staff_release'))}</button>`);
      const members = (tb.members || []).map((m) => esc(m.name) + (m.unpaid ? ` <span class="faint">(${money(m.unpaid)})</span>` : '')).join(', ');
      return `
        <div class="table-row">
          <span class="tr-name">${esc(tb.label)} ${tb.vip ? `<span class="vip-mark">${esc(t('vip'))}</span>` : ''}</span>
          <span class="status ${esc(tb.status)}">${esc(t('status_' + tb.status))}</span>
          <span class="tr-info">
            <span>${(tb.members || []).length}/${tb.capacity}</span>
            ${tb.owner ? `<span>${esc(t('host_owner'))}: ${esc(tb.owner)}</span>` : ''}
            ${tb.reservedFor ? `<span>${esc(tb.reservedFor)}</span>` : ''}
            ${members ? `<span>${members}</span>` : ''}
            ${tb.unpaid ? `<span class="gold">${t('staff_unpaid', { amount: money(tb.unpaid) })}</span>` : ''}
            ${tb.timer ? `<span class="num">${clock(tb.timer)}</span>` : ''}
            ${tb.openFor ? `<span>${esc(t('staff_open_for', { t: ago(tb.openFor) }))}</span>` : ''}
            ${tb.hookahs ? `<span>${tb.hookahs} × <img src="${ICON_PATH}hookah.svg" alt="" style="width:1rem;display:inline-block;vertical-align:middle"></span>` : ''}
          </span>
          <span class="tr-actions">${actions.join('')}</span>
        </div>`;
    }).join('');
    return `<div class="table-rows">${rows}</div>`;
  }

  function staffSales() {
    if (!S.sales) {
      loadSales();
      return `<div class="empty">${spinner()}<span>${esc(t('loading'))}</span></div>`;
    }
    const today = S.sales.today || {};
    const max = Math.max(1, ...S.sales.days.map((d) => d.revenue));
    const bars = S.sales.days.map((d) => `
      <div class="b"><em>${esc(moneyText(d.revenue))}</em><i style="height:${Math.round((d.revenue / max) * 100)}%"></i><span>${esc(d.date.slice(5))}</span></div>`).join('');
    const top = (S.sales.top || []).map((item, i) => `<li><span class="faint">${i + 1}</span><span>${esc(item.label)}</span><b>× ${item.qty}</b></li>`).join('');
    return `
      <div class="stats">
        <div class="stat"><div class="s-label">${esc(t('staff_revenue'))} · ${esc(t('staff_sales_today'))}</div><div class="s-value">${money(today.revenue)}</div></div>
        <div class="stat"><div class="s-label">${esc(t('staff_tips'))}</div><div class="s-value">${money(today.tips)}</div></div>
        <div class="stat"><div class="s-label">${esc(t('staff_orders_count'))}</div><div class="s-value num">${today.orders || 0}</div></div>
        <div class="stat"><div class="s-label">${esc(t('staff_payments_count'))}</div><div class="s-value num">${today.payments || 0}</div></div>
      </div>
      <div class="sales-grid">
        <div class="card"><h3 class="h-section">${esc(t('staff_week'))}</h3><div class="bars">${bars}</div></div>
        <div class="card"><h3 class="h-section">${esc(t('staff_top'))}</h3><ul class="top-list">${top || `<li class="faint">—</li>`}</ul></div>
      </div>
      ${S.sales.persisted ? '' : `<div class="notice warn" style="margin-top:1rem">${esc(t('staff_persist_off'))}</div>`}`;
  }

  function staffStock() {
    const items = (S.staff.stock || []).map((item) => `
      <div class="stock-item ${item.stock < 5 ? 'low' : ''}">
        <span>${esc(item.label)}</span>
        <span><b class="num">${item.stock}</b>
        <button class="btn sm" type="button" data-action="staffRestock" data-id="${esc(item.id)}">${esc(t('staff_restock'))}</button></span>
      </div>`).join('');
    return `
      <div style="margin-bottom:1rem"><button class="btn outline-gold" type="button" data-action="staffRestock">${esc(t('staff_restock_all'))}</button></div>
      <div class="stock-grid">${items}</div>`;
  }

  function staffLogs() {
    if (!S.logs) {
      loadLogs();
      return `<div class="empty">${spinner()}<span>${esc(t('loading'))}</span></div>`;
    }
    const cats = [null, 'order', 'payment', 'table', 'hookah', 'staff', 'security', 'system'];
    const chips = cats.map((c) => `<button class="chip ${S.logCategory === c ? 'active' : ''}" type="button" data-action="logCategory" data-cat="${c || ''}">${esc(c ? t('log_' + c) : t('staff_logs_all'))}</button>`).join('');
    const rows = S.logs.map((e) => {
      const time = new Date(e.time * 1000);
      return `<div class="log-row ${esc(e.level)}"><time>${String(time.getHours()).padStart(2, '0')}:${String(time.getMinutes()).padStart(2, '0')}</time><span class="tag">${esc(t('log_' + e.category))}</span><span>${esc(e.message)}</span></div>`;
    }).join('');
    return `<div class="filters" style="margin-bottom:1rem">${chips}</div><div class="log-list">${rows || `<div class="faint">—</div>`}</div>`;
  }

  function staffBusiness() {
    const open = S.staff.businessManualOpen !== false;
    return `
      <div class="card business-card">
        <div class="switch-row">
          <h3 class="h-display" style="font-size:1.4rem">${esc(t(S.staff.businessOpen ? 'staff_business_open' : 'staff_business_closed'))}</h3>
          <button class="btn ${open ? 'danger' : 'gold'}" type="button" data-action="staffBusiness" data-open="${open ? '0' : '1'}">${esc(t(open ? 'staff_close_btn' : 'staff_open_btn'))}</button>
        </div>
        <div class="muted">${esc(t('staff_mode', { mode: t('mode_' + S.staff.mode) }))}</div>
      </div>`;
  }

  async function loadSales() {
    if (busy('sales')) return;
    const result = await call('staffAction', { action: 'sales' }, { busy: 'sales', rerender: false, toastSuccess: false });
    S.sales = result.ok ? result.data : { today: {}, days: [], top: [], persisted: true };
    S.sales.days = arr(S.sales.days);
    S.sales.top = arr(S.sales.top);
    S.sales.today = S.sales.today || {};
    render();
  }

  async function loadLogs() {
    if (busy('logs')) return;
    const result = await call('staffAction', { action: 'logs', category: S.logCategory }, { busy: 'logs', rerender: false, toastSuccess: false });
    S.logs = result.ok ? arr(result.data) : [];
    render();
  }

  // ── modals ──────────────────────────────────────────────

  function renderModal() {
    const m = S.modal;
    if (!m) {
      modalEl.hidden = true;
      modalEl.innerHTML = '';
      return;
    }
    const renderers = {
      flavor: modalFlavor,
      hookahFlavor: modalHookahFlavor,
      hookahCoals: modalHookahCoals,
      players: modalPlayers,
      confirm: modalConfirm,
      reserve: modalReserve,
    };
    const html = (renderers[m.type] || (() => ''))(m);
    if (!html) {
      S.modal = null;
      modalEl.hidden = true;
      return;
    }
    const key = m.type + ':' + (m.productId || m.sessionId || m.tableId || '');
    const fresh = key !== lastModalKey || modalEl.hidden;
    lastModalKey = key;
    modalEl.innerHTML = html;
    modalEl.classList.toggle('static', !fresh);
    modalEl.hidden = false;
    const input = modalEl.querySelector('[autofocus]');
    if (input && document.activeElement !== input) input.focus();
  }

  function flavorButtons(product, selected, max) {
    return S.catalog.flavors.filter((f) => !product.allowedFlavors || product.allowedFlavors.includes(f.id)).map((f) => {
      const active = selected.includes(f.id);
      const disabled = !active && selected.length >= max && max > 1;
      return `
        <button type="button" class="flavor ${active ? 'active' : ''}" data-action="pickFlavor" data-id="${esc(f.id)}" ${disabled ? 'disabled' : ''} style="--c:${esc(f.color || '#c9a45c')}">
          <i></i><span class="f-name">${esc(f.label)}</span><span class="f-price">${f.price ? '+' + esc(moneyText(f.price)) : ''}</span>
        </button>`;
    }).join('');
  }

  function modalHead(title, subtitle) {
    return `
      <div class="modal-head">
        <div><h3>${esc(title)}</h3>${subtitle ? `<div class="muted small">${subtitle}</div>` : ''}</div>
        <button class="icon-btn" type="button" data-action="closeModal"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18"/></svg></button>
      </div>`;
  }

  function modalFlavor(m) {
    const product = products.get(m.productId);
    if (!product) return '';
    const max = product.maxFlavors || 1;
    const price = unitPrice(product, m.selected) * m.qty;
    return `
      <div class="modal wide">
        ${modalHead(product.label, esc(max > 1 ? t('flavor_title_multi', { n: max }) : t('flavor_title')) + (max > 1 ? ' · ' + esc(t('flavor_selected', { n: m.selected.length, max })) : ''))}
        <div class="flavor-grid">${flavorButtons(product, m.selected, max)}</div>
        <div class="modal-foot" style="justify-content:space-between;align-items:center">
          <span class="stepper">
            <button type="button" data-action="flavorQty" data-delta="1">+</button>
            <span>${m.qty}</span>
            <button type="button" data-action="flavorQty" data-delta="-1">−</button>
          </span>
          <button class="btn gold" type="button" data-action="flavorAdd" ${m.selected.length ? '' : 'disabled'}>
            ${m.selected.length ? t('flavor_add', { price: money(price) }) : esc(t('flavor_none'))}
          </button>
        </div>
      </div>`;
  }

  function sessionOf(m) {
    return (S.me.hookahs || []).find((h) => h.id === m.sessionId);
  }

  function serviceAccountPicker() {
    if (S.settings.timing !== 'on_order' || S.settings.moneyMode !== 'money') return '';
    return `<div class="option-grid">${(S.settings.accounts || []).map((a) => `<button type="button" class="option ${S.orderAccount === a.id ? 'active' : ''}" data-action="orderAccount" data-id="${esc(a.id)}">${esc(a.label)}</button>`).join('')}</div>`;
  }

  function modalHookahFlavor(m) {
    const session = sessionOf(m);
    const product = session && products.get(session.typeId);
    if (!session || !product) return '';
    const max = product.maxFlavors || 1;
    const base = (S.settings.flavorChange && S.settings.flavorChange.price) || 0;
    const price = base + m.selected.reduce((sum, id) => sum + ((flavors.get(id) || {}).price || 0), 0);
    return `
      <div class="modal wide">
        ${modalHead(t('hookah_change_title'), esc(session.label) + ' · ' + t('hookah_change_price', { price: money(price) }))}
        <div class="flavor-grid">${flavorButtons(product, m.selected, max)}</div>
        ${serviceAccountPicker()}
        <div class="modal-foot">
          <button class="btn ghost" type="button" data-action="closeModal">${esc(t('cancel'))}</button>
          <button class="btn gold" type="button" data-action="hookahFlavorConfirm" ${m.selected.length && !busy('hookahAction') ? '' : 'disabled'}>${t('hookah_confirm', { price: money(price) })}</button>
        </div>
      </div>`;
  }

  function modalHookahCoals(m) {
    const session = sessionOf(m);
    if (!session) return '';
    const cfg = S.settings.coalRefresh || {};
    return `
      <div class="modal">
        ${modalHead(t('hookah_coals_title'), esc(session.label))}
        <p class="muted">${esc(t('hookah_coals_desc', { m: Math.round((cfg.extendSeconds || 600) / 60), used: session.refreshes || 0, max: cfg.maxRefreshes || 3 }))}</p>
        ${serviceAccountPicker()}
        <div class="modal-foot">
          <button class="btn ghost" type="button" data-action="closeModal">${esc(t('cancel'))}</button>
          <button class="btn gold" type="button" data-action="hookahCoalsConfirm" ${busy('hookahAction') ? 'disabled' : ''}>${t('hookah_confirm', { price: money(cfg.price || 0) })}</button>
        </div>
      </div>`;
  }

  function modalPlayers(m) {
    const list = m.players;
    const body = !list ? `<div class="empty">${spinner()}</div>`
      : list.length ? `<div class="player-list">${list.map((p) => `
        <div class="pl"><span>${esc(p.name)} <span class="faint small">#${p.id}</span></span>
          <button class="btn sm outline-gold" type="button" data-action="${m.mode === 'seat' ? 'seatGuestPick' : 'invitePick'}" data-id="${p.id}">${esc(t('invite_btn'))}</button></div>`).join('')}</div>`
        : `<div class="empty">${esc(t(m.mode === 'seat' ? 'staff_nearby_empty' : 'invite_empty'))}</div>`;
    return `<div class="modal">${modalHead(t(m.mode === 'seat' ? 'staff_nearby_title' : 'invite_title'))}${body}</div>`;
  }

  function modalConfirm(m) {
    return `
      <div class="modal">
        ${modalHead(m.title)}
        <p class="muted" style="margin:0">${m.html}</p>
        <div class="modal-foot">
          <button class="btn ghost" type="button" data-action="closeModal">${esc(m.no || t('cancel'))}</button>
          <button class="btn ${m.danger ? 'danger' : 'gold'}" type="button" data-action="confirmYes">${esc(m.yes || t('confirm'))}</button>
        </div>
      </div>`;
  }

  function modalReserve(m) {
    return `
      <div class="modal">
        ${modalHead(t('staff_reserve'), esc(t('staff_reserve_name')))}
        <input class="input" id="reserveName" maxlength="32" autofocus placeholder="${esc(t('staff_reserve_placeholder'))}" value="${esc(m.name || '')}">
        <div class="modal-foot">
          <button class="btn ghost" type="button" data-action="closeModal">${esc(t('cancel'))}</button>
          <button class="btn gold" type="button" data-action="reserveConfirm">${esc(t('confirm'))}</button>
        </div>
      </div>`;
  }

  function closeModal() {
    S.modal = null;
    lastModalKey = null;
    renderModal();
  }

  // ── actions ─────────────────────────────────────────────

  async function staffAction(payload, options) {
    const result = await call('staffAction', payload, Object.assign({ busy: 'staff:' + payload.action + ':' + (payload.orderId || payload.tableId || '') }, options || {}));
    return result;
  }

  const actions = {
    close: () => close(),
    closeModal: () => closeModal(),
    tab: (el) => {
      const panel = el.dataset.panel;
      S.panel = panel;
      S.modal = null;
      post('switchPanel', { panel });
      if (panel === 'bill') { S.billMode = S.me.isOwner && S.settings.allowTableBill ? 'table' : 'personal'; loadBill(); }
      if (panel === 'staff') {
        S.sales = null;
        S.logs = null;
        call('staffOpen', {}, { toastSuccess: false }).then((r) => { if (r.ok) { S.staff = normStaff(r.data); render(); } });
      }
      render();
    },
    party: (el) => { S.party = Number(el.dataset.n); render(); },
    requestTable: async () => {
      const result = await call('requestTable', { partySize: S.party });
      if (result.ok) render();
    },
    sit: (el) => { post('sit', { tableId: Number(el.dataset.table) }); hide(); },
    leaveTable: () => call('leaveTable', {}),
    openInvite: async () => {
      S.modal = { type: 'players', mode: 'invite', players: null };
      renderModal();
      const result = await call('nearbyPlayers', {}, { rerender: false, toastSuccess: false });
      if (S.modal && S.modal.type === 'players') { S.modal.players = result.ok ? arr(result.data) : []; renderModal(); }
    },
    invitePick: async (el) => {
      const result = await call('invite', { target: Number(el.dataset.id) });
      if (result.ok) closeModal();
    },
    category: (el) => { S.category = el.dataset.id; render(); },
    filter: (el) => {
      const tag = el.dataset.tag;
      if (S.filters.has(tag)) S.filters.delete(tag); else S.filters.add(tag);
      render();
    },
    add: (el) => {
      const product = products.get(el.dataset.id);
      if (!product) return;
      if (product.kind === 'hookah') {
        S.modal = { type: 'flavor', productId: product.id, selected: [], qty: 1 };
        renderModal();
      } else {
        addToCart(product.id, [], 1);
      }
    },
    pickFlavor: (el) => {
      const m = S.modal;
      if (!m) return;
      const id = el.dataset.id;
      const product = m.type === 'flavor' ? products.get(m.productId) : products.get((sessionOf(m) || {}).typeId);
      const max = (product && product.maxFlavors) || 1;
      if (m.selected.includes(id)) m.selected = m.selected.filter((f) => f !== id);
      else if (max === 1) m.selected = [id];
      else if (m.selected.length < max) m.selected.push(id);
      renderModal();
    },
    flavorQty: (el) => {
      const m = S.modal;
      const product = m && products.get(m.productId);
      if (!product) return;
      m.qty = Math.max(1, Math.min(product.maxQty || 2, m.qty + Number(el.dataset.delta)));
      renderModal();
    },
    flavorAdd: () => {
      const m = S.modal;
      if (!m || !m.selected.length) return;
      addToCart(m.productId, m.selected, m.qty);
      closeModal();
    },
    qty: (el) => changeQty(el.dataset.key, Number(el.dataset.delta)),
    removeLine: (el) => { S.cart = S.cart.filter((l) => l.key !== el.dataset.key); render(); },
    clearCart: () => { S.cart = []; render(); },
    orderAccount: (el) => { S.orderAccount = el.dataset.id; render(); },
    placeOrder: async () => {
      if (!S.cart.length) return;
      const result = await call('placeOrder', {
        lines: S.cart.map((l) => ({ id: l.id, qty: l.qty, flavors: l.flavors })),
        requestId: requestId(),
        account: S.orderAccount,
      });
      if (result.ok) {
        S.cart = [];
        S.panel = 'orders';
        post('switchPanel', { panel: 'orders' });
        render();
      }
    },
    cancelOrder: (el) => call('cancelOrder', { orderId: Number(el.dataset.id) }),
    consume: (el) => call('consume', { itemId: el.dataset.id }, { busy: 'consume' }),
    hookahUse: (el) => call('hookahAction', { action: 'use', sessionId: Number(el.dataset.id) }, { toastSuccess: false }),
    hookahFlavor: (el) => {
      const session = (S.me.hookahs || []).find((h) => h.id === Number(el.dataset.id));
      if (session) { S.modal = { type: 'hookahFlavor', sessionId: session.id, selected: session.flavors.slice() }; renderModal(); }
    },
    hookahCoals: (el) => { S.modal = { type: 'hookahCoals', sessionId: Number(el.dataset.id) }; renderModal(); },
    hookahEnd: (el) => call('hookahAction', { action: 'end', sessionId: Number(el.dataset.id) }),
    hookahFlavorConfirm: async () => {
      const m = S.modal;
      if (!m) return;
      const result = await call('hookahAction', { action: 'flavor', sessionId: m.sessionId, flavors: m.selected, account: S.orderAccount });
      if (result.ok) closeModal();
    },
    hookahCoalsConfirm: async () => {
      const m = S.modal;
      if (!m) return;
      const result = await call('hookahAction', { action: 'coals', sessionId: m.sessionId, account: S.orderAccount });
      if (result.ok) closeModal();
    },
    billMode: (el) => { S.billMode = el.dataset.mode; loadBill(); },
    reloadBill: () => loadBill(),
    tip: (el) => { S.tip = Number(el.dataset.p); render(); },
    billAccount: (el) => { S.billAccount = el.dataset.id; render(); },
    confirmPay: () => {
      const bill = S.bill;
      if (!bill || !bill.token) return;
      const totals = billTotals(bill);
      if (bill.moneyMode !== 'money') return doPay();
      const account = (bill.accounts || []).find((a) => a.id === S.billAccount);
      S.modal = {
        type: 'confirm',
        title: t('bill_confirm_title'),
        html: t('bill_confirm_text', { amount: money(totals.total), account: esc(account ? account.label : '') }),
        yes: t('bill_confirm_yes'),
        no: t('bill_confirm_no'),
        onYes: doPay,
      };
      renderModal();
    },
    confirmYes: () => {
      const m = S.modal;
      closeModal();
      if (m && typeof m.onYes === 'function') m.onYes();
    },
    staffTab: (el) => {
      S.staffTab = el.dataset.tab;
      if (S.staffTab === 'sales') S.sales = null;
      if (S.staffTab === 'logs') S.logs = null;
      render();
    },
    staffOrder: (el) => staffAction({ action: 'orderStatus', orderId: Number(el.dataset.id), status: el.dataset.status }),
    staffCancel: (el) => staffAction({ action: 'orderCancel', orderId: Number(el.dataset.id), reason: 'staff' }),
    staffTable: (el) => staffAction({ action: 'table', tableId: Number(el.dataset.id), op: el.dataset.op }),
    staffReserve: (el) => { S.modal = { type: 'reserve', tableId: Number(el.dataset.id) }; renderModal(); },
    reserveConfirm: async () => {
      const m = S.modal;
      const input = $('#reserveName');
      if (!m) return;
      const result = await staffAction({ action: 'table', tableId: m.tableId, op: 'reserve', name: input ? input.value : '' });
      if (result.ok) closeModal();
    },
    staffSeat: async (el) => {
      const tableId = Number(el.dataset.id);
      S.modal = { type: 'players', mode: 'seat', tableId, players: null };
      renderModal();
      const result = await call('staffAction', { action: 'nearby' }, { busy: 'nearby', rerender: false, toastSuccess: false });
      if (S.modal && S.modal.type === 'players') { S.modal.players = result.ok ? arr(result.data) : []; renderModal(); }
    },
    seatGuestPick: async (el) => {
      const m = S.modal;
      if (!m) return;
      const result = await staffAction({ action: 'table', tableId: m.tableId, op: 'seat_guest', target: Number(el.dataset.id) });
      if (result.ok) closeModal();
    },
    staffRequestPay: (el) => staffAction({ action: 'requestPayment', tableId: Number(el.dataset.id) }),
    staffRelease: (el) => {
      const tableId = Number(el.dataset.id);
      S.modal = {
        type: 'confirm',
        danger: true,
        title: t('staff_release'),
        html: esc(t('staff_release_confirm', { table: el.dataset.label })),
        yes: t('staff_release'),
        onYes: () => staffAction({ action: 'table', tableId, op: 'release' }),
      };
      renderModal();
    },
    staffRestock: (el) => staffAction({ action: 'restock', productId: el.dataset.id || undefined }),
    staffBusiness: (el) => staffAction({ action: 'business', open: el.dataset.open === '1' }),
    logCategory: (el) => { S.logCategory = el.dataset.cat || null; S.logs = null; render(); },
  };

  async function doPay() {
    const bill = S.bill;
    if (!bill) return;
    const result = await call('pay', { token: bill.token, account: S.billAccount, tip: S.tip }, { toastSuccess: true });
    if (result.ok) {
      S.billResult = result.data;
      render();
    } else if (result.code === 'bill_changed' || result.code === 'token_invalid' || result.code === 'insufficient_funds' || result.code === 'payment_failed') {
      loadBill();
    }
  }

  document.addEventListener('click', (event) => {
    const contextButton = event.target.closest('[data-context-index]');
    if (contextButton) {
      selectContext(Number(contextButton.dataset.contextIndex));
      return;
    }
    const el = event.target.closest('[data-action]');
    if (!el || el.disabled) return;
    const handler = actions[el.dataset.action];
    if (handler) handler(el, event);
  });

  modalEl.addEventListener('click', (event) => {
    if (event.target === modalEl) closeModal();
  });

  document.addEventListener('input', (event) => {
    if (event.target.id === 'menuSearch') {
      S.search = event.target.value;
      render();
    }
  });

  document.addEventListener('change', (event) => {
    if (event.target.id === 'menuSort') {
      S.sort = event.target.value;
      render();
    }
  });

  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') {
      event.preventDefault();
      if (S.contextOpen) closeContext(true);
      else if (S.modal) closeModal();
      else if (S.open) close();
      return;
    }
    if (S.contextOpen && /^[1-9]$/.test(event.key)) {
      selectContext(Number(event.key));
      return;
    }
    if (event.key === 'Enter' && S.modal && S.modal.type === 'reserve') actions.reserveConfirm();
  });

  // ── timers ──────────────────────────────────────────────

  function tickTimers() {
    const now = Date.now();
    document.querySelectorAll('[data-countdown]').forEach((el) => {
      const left = Math.max(0, (Number(el.dataset.countdown) - now) / 1000);
      const format = el.dataset.countdownFormat;
      el.textContent = format ? t(format, { t: clock(left) }) : clock(left);
    });
    document.querySelectorAll('[data-bar-until]').forEach((el) => {
      const left = Math.max(0, (Number(el.dataset.barUntil) - now) / 1000);
      const total = Math.max(1, Number(el.dataset.barTotal));
      el.style.width = Math.min(100, (left / total) * 100) + '%';
    });
  }
  setInterval(tickTimers, 1000);

  // ── toasts / prompt / context / clipboard ───────────────

  function toast(message, type, duration) {
    if (!message) return;
    const kind = ['success', 'error', 'warning', 'info'].includes(type) ? type : 'info';
    const box = $('#toasts');
    // the same message twice in a row only refreshes the visible toast
    const existing = Array.from(box.children).find((el) => el.dataset.message === message && !el.classList.contains('out'));
    if (existing) {
      clearTimeout(Number(existing.dataset.timer));
      existing.dataset.timer = String(setTimeout(() => dismissToast(existing), Math.max(1500, Math.min(15000, duration || 4500))));
      existing.animate([{ transform: 'scale(1.03)' }, { transform: 'none' }], { duration: 180 });
      return;
    }
    const el = document.createElement('div');
    el.dataset.message = message;
    el.className = `toast ${kind}`;
    el.innerHTML = `<span class="t-icon">${svgIcon(kind)}</span><span>${esc(message)}</span>`;
    box.appendChild(el);
    while (box.children.length > 4) box.removeChild(box.firstChild);
    el.dataset.timer = String(setTimeout(() => dismissToast(el), Math.max(1500, Math.min(15000, duration || 4500))));
  }

  function dismissToast(el) {
    el.classList.add('out');
    setTimeout(() => el.remove(), 320);
  }

  function showPrompt(data) {
    const el = $('#prompt');
    if (!data.show) { el.hidden = true; return; }
    el.querySelector('.prompt-label').textContent = data.label || '';
    el.querySelector('.prompt-more').hidden = !data.more;
    el.hidden = false;
  }

  function openContext(options) {
    const el = $('#context');
    S.contextOpen = true;
    el.innerHTML = `<h4>${esc(t('context_title'))}</h4>` + options.map((o, i) => `
      <button type="button" data-context-index="${o.index}"><kbd>${i + 1}</kbd><span>${esc(o.label)}</span></button>`).join('');
    el.hidden = false;
    $('#prompt').hidden = true;
    const first = el.querySelector('button');
    if (first) first.focus();
  }

  function closeContext(notify) {
    S.contextOpen = false;
    $('#context').hidden = true;
    if (notify) post('contextClose', {});
  }

  function selectContext(index) {
    closeContext(false);
    post('contextSelect', { index });
  }

  function copyText(text) {
    if (!text) return;
    const area = document.createElement('textarea');
    area.value = text;
    area.style.position = 'fixed';
    area.style.opacity = '0';
    document.body.appendChild(area);
    area.select();
    try { document.execCommand('copy'); } catch (err) { /* clipboard not available */ }
    area.remove();
    post('copyDone', {});
  }

  // ── start ───────────────────────────────────────────────

  window.CCH = { handleMessage, state: S, setPost: (fn) => { post = fn; } };

  if (IN_GAME) {
    post('ready', {});
  } else {
    // Browser preview: load sample data from tests/nui (not shipped to players).
    document.body.classList.add('dev');
    const banner = $('#devBanner');
    banner.textContent = t('dev_banner');
    banner.hidden = false;
    const script = document.createElement('script');
    script.src = '../tests/nui/mock-data.js';
    script.onload = () => {
      const mock = document.createElement('script');
      mock.src = '../tests/nui/mock.js';
      document.head.appendChild(mock);
    };
    document.head.appendChild(script);
  }
})();

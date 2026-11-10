// Content script running on Odoo ERP (http://erp.fivafood.co.id:8069)
console.log('[Lucifax-Odoo] Assistant loaded on Odoo ERP');

(function() {
  let currentPayload = null;

  // 1. Create floating UI widget
  function createFloatingWidget() {
    if (document.getElementById('lucifax-odoo-widget')) return;

    const widget = document.createElement('div');
    widget.id = 'lucifax-odoo-widget';
    widget.style.cssText = `
      position: fixed;
      top: 65px;
      right: 20px;
      width: 320px;
      background: #0F172A;
      color: #F8FAFC;
      border: 1.5px solid #38BDF8;
      border-radius: 12px;
      box-shadow: 0 10px 25px -5px rgba(0, 0, 0, 0.6), 0 8px 10px -6px rgba(0, 0, 0, 0.4);
      z-index: 999999;
      font-family: system-ui, -apple-system, sans-serif;
      font-size: 12px;
      overflow: hidden;
      transition: all 0.2s ease;
    `;

    widget.innerHTML = `
      <div id="lucifax-header" style="
        background: linear-gradient(135deg, #1E293B, #0F172A);
        padding: 10px 14px;
        display: flex;
        align-items: center;
        justify-content: space-between;
        border-bottom: 1px solid #334155;
        cursor: move;
        user-select: none;
      ">
        <div style="display: flex; align-items: center; gap: 8px;">
          <span style="font-size: 16px;">⚡</span>
          <strong style="color: #38BDF8; font-size: 13px;">Lucifax Odoo Assistant v1.2.5</strong>
        </div>
        <div style="display: flex; gap: 6px;">
          <button id="lucifax-toggle-btn" style="
            background: #334155;
            border: none;
            color: #94A3B8;
            border-radius: 4px;
            width: 22px;
            height: 22px;
            cursor: pointer;
            font-weight: bold;
          ">−</button>
        </div>
      </div>

      <div id="lucifax-body" style="padding: 12px;">
        <div id="lucifax-invoice-box" style="
          background: #1E293B;
          border: 1px solid #334155;
          border-radius: 8px;
          padding: 8px 10px;
          margin-bottom: 8px;
        ">
          <div id="lucifax-invoice-status" style="color: #94A3B8; font-size: 11px; line-height: 1.4;">
            Belum ada transaksi dipilih.<br/>
            Klik <b>[Siapkan ke Odoo]</b> di Lucifax PFS.
          </div>
        </div>

        <div id="lucifax-paste-section" style="margin-bottom: 10px;">
          <input id="lucifax-paste-input" type="text" placeholder="📋 Klik di sini lalu tekan Ctrl+V" style="
            width: 100%;
            box-sizing: border-box;
            padding: 7px 10px;
            background: #020617;
            border: 1.5px dashed #38BDF8;
            border-radius: 6px;
            color: #F8FAFC;
            font-size: 11px;
            outline: none;
            text-align: center;
            cursor: pointer;
          " />
        </div>

        <div style="display: flex; flex-direction: column; gap: 8px;">
          <button id="btn-fill-pt-po" style="
            background: #0284C7;
            color: #FFFFFF;
            border: none;
            padding: 9px 12px;
            border-radius: 6px;
            font-weight: bold;
            font-size: 12px;
            cursor: pointer;
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 6px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.2);
          ">
            <span>⚡</span> Auto-Fill PT PO (Purchase)
          </button>

          <button id="btn-fill-pt-so" style="
            background: #D97706;
            color: #FFFFFF;
            border: none;
            padding: 9px 12px;
            border-radius: 6px;
            font-weight: bold;
            font-size: 12px;
            cursor: pointer;
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 6px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.2);
          ">
            <span>⚡</span> Auto-Fill PT SO (Sales PT)
          </button>

          <button id="btn-fill-cv-so" style="
            background: #10B981;
            color: #FFFFFF;
            border: none;
            padding: 9px 12px;
            border-radius: 6px;
            font-weight: bold;
            font-size: 12px;
            cursor: pointer;
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 6px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.2);
          ">
            <span>⚡</span> Auto-Fill CV SO (Sales CV)
          </button>
        </div>

        <div style="margin-top: 10px; background: #0F172A; border: 1px solid #334155; border-radius: 6px; padding: 6px 8px;">
          <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 4px;">
            <span style="font-size: 10px; color: #94A3B8; font-weight: bold;">Kecepatan / Pacing:</span>
            <span id="lucifax-speed-badge" style="font-size: 10px; color: #38BDF8; font-weight: bold;">🛡️ Mode Aman</span>
          </div>
          <select id="lucifax-speed-select" style="
            width: 100%;
            background: #1E293B;
            color: #F8FAFC;
            border: 1px solid #475569;
            border-radius: 4px;
            padding: 4px 6px;
            font-size: 11px;
            outline: none;
            cursor: pointer;
          ">
            <option value="safe" selected>🛡️ Mode Aman / Jaringan Lambat (Rekomendasi)</option>
            <option value="ultra_safe">🐢 Mode Sangat Santai (Extra Verifikasi)</option>
            <option value="fast">⚡ Mode Cepat (Jaringan Cepat)</option>
          </select>
        </div>

        <div style="margin-top: 10px; display: flex; justify-content: space-between; align-items: center;">
          <button id="btn-paste-clipboard" style="
            background: #1E293B;
            border: 1px solid #38BDF8;
            color: #38BDF8;
            border-radius: 4px;
            padding: 5px 9px;
            font-size: 11px;
            font-weight: bold;
            cursor: pointer;
          ">📋 Ambil / Tempel (Ctrl+V)</button>
          
          <span style="font-size: 10px; color: #64748B;">Mode: Draft Only</span>
        </div>

        <div id="lucifax-log" style="
          margin-top: 10px;
          padding: 6px 8px;
          background: #020617;
          border-radius: 4px;
          font-family: monospace;
          font-size: 10.5px;
          color: #38BDF8;
          max-height: 80px;
          overflow-y: auto;
          display: none;
        "></div>
      </div>
    `;

    document.body.appendChild(widget);

    // Make widget draggable
    const header = document.getElementById('lucifax-header');
    let isDragging = false;
    let offsetX, offsetY;

    header.addEventListener('mousedown', (e) => {
      isDragging = true;
      offsetX = e.clientX - widget.getBoundingClientRect().left;
      offsetY = e.clientY - widget.getBoundingClientRect().top;
    });

    document.addEventListener('mousemove', (e) => {
      if (isDragging) {
        widget.style.left = `${e.clientX - offsetX}px`;
        widget.style.top = `${e.clientY - offsetY}px`;
        widget.style.right = 'auto';
      }
    });

    document.addEventListener('mouseup', () => {
      isDragging = false;
    });

    // Toggle minimize
    const toggleBtn = document.getElementById('lucifax-toggle-btn');
    const body = document.getElementById('lucifax-body');
    let isMinimized = false;

    toggleBtn.addEventListener('click', () => {
      isMinimized = !isMinimized;
      body.style.display = isMinimized ? 'none' : 'block';
      toggleBtn.innerText = isMinimized ? '+' : '−';
      widget.style.width = isMinimized ? '200px' : '320px';
    });

    // Button & input event listeners
    document.getElementById('btn-fill-pt-po').addEventListener('click', () => runAutoFill('PT_PO'));
    document.getElementById('btn-fill-pt-so').addEventListener('click', () => runAutoFill('PT_SO'));
    document.getElementById('btn-fill-cv-so').addEventListener('click', () => runAutoFill('CV_SO'));
    document.getElementById('btn-paste-clipboard').addEventListener('click', () => pasteFromClipboard(true));

    const pasteInput = document.getElementById('lucifax-paste-input');
    if (pasteInput) {
      pasteInput.addEventListener('focus', () => pasteInput.select());
      pasteInput.addEventListener('paste', (e) => {
        const text = (e.clipboardData || window.clipboardData)?.getData('text');
        if (text && applyPayloadText(text, true)) {
          pasteInput.value = '';
          pasteInput.blur();
        }
      });
      pasteInput.addEventListener('input', () => {
        const text = pasteInput.value;
        if (text && applyPayloadText(text, true)) {
          pasteInput.value = '';
          pasteInput.blur();
        }
      });
    }

    const speedSelect = document.getElementById('lucifax-speed-select');
    const speedBadge = document.getElementById('lucifax-speed-badge');
    if (speedSelect && speedBadge) {
      speedSelect.addEventListener('change', () => {
        if (speedSelect.value === 'ultra_safe') speedBadge.innerText = '🐢 Sangat Santai';
        else if (speedSelect.value === 'fast') speedBadge.innerText = '⚡ Mode Cepat';
        else speedBadge.innerText = '🛡️ Mode Aman';
      });
    }
  }

  // Helper log
  function logMessage(msg, isSuccess = false, isError = false) {
    const logBox = document.getElementById('lucifax-log');
    if (!logBox) return;
    logBox.style.display = 'block';
    logBox.style.color = isError ? '#F87171' : (isSuccess ? '#4ADE80' : '#38BDF8');
    logBox.innerHTML = `> ${msg}`;
    logBox.scrollTop = logBox.scrollHeight;
  }

  // Update UI with payload info
  function updateInvoiceBox(payload) {
    currentPayload = payload;
    const box = document.getElementById('lucifax-invoice-status');
    const pasteInput = document.getElementById('lucifax-paste-input');
    if (!box) return;

    if (payload && payload.invoiceNo) {
      box.innerHTML = `
        <div style="font-weight: bold; color: #38BDF8; font-size: 12px; margin-bottom: 2px;">
          Invoice #${payload.invoiceNo} - ${payload.customerAlias || payload.customerName}
        </div>
        <div style="color: #CBD5E1; font-size: 11px;">
          Kota: <b>${payload.city}</b> | Total: <b>${payload.items ? payload.items.length : 0} Item</b> (${payload.grandTotalCarton || 0} Ktn)
        </div>
        <div style="color: #4ADE80; font-size: 10.5px; margin-top: 4px;">
          Rp ${Number(payload.grandTotal || 0).toLocaleString('id-ID')}
        </div>
      `;
      if (pasteInput) {
        pasteInput.placeholder = `✅ Invoice #${payload.invoiceNo} Siap Diisi`;
        pasteInput.style.borderColor = '#4ADE80';
        pasteInput.style.color = '#4ADE80';
      }
    } else {
      box.innerHTML = `
        <div style="color: #94A3B8; font-size: 11px; line-height: 1.4;">
          Belum ada transaksi dipilih.<br/>
          Klik <b>[Siapkan ke Odoo]</b> di Lucifax PFS.
        </div>
      `;
    }
  }

  // Safe wrapper for chrome.runtime.sendMessage to prevent "Extension context invalidated" errors
  function safeSendMessage(message, callback) {
    try {
      if (typeof chrome !== 'undefined' && chrome.runtime && chrome.runtime.sendMessage) {
        chrome.runtime.sendMessage(message, (response) => {
          if (chrome.runtime && chrome.runtime.lastError) {
            // Silently ignore context invalidation
          }
          if (callback) callback(response);
        });
        return;
      }
    } catch (_) {}
    if (callback) callback(null);
  }

  // Check storage on load
  function loadStoredPayload() {
    safeSendMessage({ action: 'GET_INVOICE_PAYLOAD' }, (response) => {
      if (response && response.payload && response.payload.invoiceNo) {
        updateInvoiceBox(response.payload);
      } else {
        updateInvoiceBox(null);
        pasteFromClipboard(false);
      }
    });
  }

  // Helper to read clipboard text in both HTTPS and HTTP contexts
  async function readClipboardText() {
    if (navigator.clipboard && navigator.clipboard.readText) {
      try {
        const text = await navigator.clipboard.readText();
        if (text) return text;
      } catch (_) {}
    }

    try {
      const ta = document.createElement('textarea');
      ta.style.position = 'fixed';
      ta.style.left = '-9999px';
      ta.style.top = '-9999px';
      ta.style.opacity = '0';
      document.body.appendChild(ta);
      ta.focus();
      document.execCommand('paste');
      const val = ta.value;
      document.body.removeChild(ta);
      if (val) return val;
    } catch (_) {}

    return null;
  }

  function applyPayloadText(text, manualTrigger = false) {
    if (!text || !text.includes('LUCIFAX_ODOO_PAYLOAD:')) {
      if (manualTrigger) logMessage('Data tidak valid / tidak ada format Lucifax!', false, true);
      return false;
    }
    try {
      const jsonStr = text.substring(text.indexOf('LUCIFAX_ODOO_PAYLOAD:') + 'LUCIFAX_ODOO_PAYLOAD:'.length).trim();
      const payload = JSON.parse(jsonStr);
      updateInvoiceBox(payload);
      safeSendMessage({ action: 'STORE_INVOICE_PAYLOAD', payload: payload });
      if (manualTrigger) logMessage(`Data Invoice #${payload.invoiceNo} berhasil dimuat!`, true);
      return true;
    } catch (e) {
      if (manualTrigger) logMessage('Gagal parse data: ' + e.message, false, true);
      return false;
    }
  }

  // Read clipboard as fallback / cross-profile sync
  async function pasteFromClipboard(manualTrigger = true) {
    const text = await readClipboardText();
    if (text && applyPayloadText(text, manualTrigger)) {
      return true;
    }

    if (manualTrigger) {
      const manual = prompt('Silakan tempelkan data (tekan Ctrl+V lalu Enter):');
      if (manual && applyPayloadText(manual, true)) {
        return true;
      }
    }
    return false;
  }

  // Sleep utility
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));

  // Helper to trigger events
  function triggerEvents(element) {
    element.dispatchEvent(new Event('input', { bubbles: true }));
    element.dispatchEvent(new Event('change', { bubbles: true }));
    element.dispatchEvent(new Event('blur', { bubbles: true }));
  }

  // Helper to find input by field name or label in Odoo DOM
  function findFieldInput(fieldName, labelKeywords = []) {
    let el = document.querySelector(`div[name="${fieldName}"] input`)
      || document.querySelector(`input[name="${fieldName}"]`)
      || document.querySelector(`[data-name="${fieldName}"] input`)
      || document.querySelector(`.o_field_widget[name="${fieldName}"] input`)
      || document.querySelector(`.o_field_many2manytags[name="${fieldName}"] input`);
    if (el) return el;

    if (labelKeywords && labelKeywords.length > 0) {
      const labels = Array.from(document.querySelectorAll('label.o_form_label, label'));
      for (const kw of labelKeywords) {
        const kwLower = kw.toLowerCase().trim();
        const matchedLabel = labels.find(l => {
          const txt = l.innerText.toLowerCase().trim();
          return txt === kwLower || txt.startsWith(kwLower);
        });
        if (matchedLabel) {
          const forId = matchedLabel.getAttribute('for');
          if (forId) {
            const byFor = document.getElementById(forId);
            if (byFor) {
              const inp = byFor.tagName === 'INPUT' ? byFor : byFor.querySelector('input');
              if (inp) return inp;
            }
          }
          const parentRow = matchedLabel.closest('tr, .o_row, .o_cell, .row, .o_group, div');
          if (parentRow) {
            const inp = parentRow.querySelector('input');
            if (inp) return inp;
          }
        }
      }
    }
    return null;
  }

  // Dismiss any unwanted Odoo modal (Record modified / Do you want to create)
  function dismissOdooModals() {
    const modals = Array.from(document.querySelectorAll('.modal, .modal-dialog, [role="dialog"]'));
    for (const modal of modals) {
      const rect = modal.getBoundingClientRect();
      if (rect.width === 0 || rect.height === 0 || modal.style.display === 'none') continue;
      const text = modal.innerText.toLowerCase();
      // 1. "Record has been modified, your changes will be discarded" -> click Cancel
      if (text.includes('discarded') || text.includes('modified') || text.includes('diabaikan')) {
        const cancelBtn = Array.from(modal.querySelectorAll('button')).find(b => 
          b.innerText.toLowerCase().includes('cancel') || 
          b.innerText.toLowerCase().includes('batal')
        );
        if (cancelBtn) {
          cancelBtn.click();
          return true;
        }
      }
      // 2. "Do you want to create X as a new Y?" -> click Cancel so it doesn't create unwanted records or freeze Odoo!
      if (text.includes('create') && (text.includes('as a new') || text.includes('apakah anda ingin membuat') || text.includes('new tags') || text.includes('new delivery address'))) {
        const cancelBtn = Array.from(modal.querySelectorAll('button')).find(b => 
          b.innerText.toLowerCase().includes('cancel') || 
          b.innerText.toLowerCase().includes('batal')
        );
        if (cancelBtn) {
          cancelBtn.click();
          return true;
        }
      }
    }
    return false;
  }
  const dismissDiscardModal = dismissOdooModals;

  // Detect if Odoo is currently busy / loading in server
  function isOdooLoading() {
    // 1. Standard loading indicators & overlays
    const loadingIndicators = Array.from(document.querySelectorAll('.o_loading, .oe_loading, .o_spinner, .o_blockUI, .blockUI, div.ui-autocomplete-loading'));
    for (const el of loadingIndicators) {
      if (!el.classList.contains('d-none') && el.style.display !== 'none') {
        const rect = el.getBoundingClientRect();
        if (rect.width > 0 && rect.height > 0) {
          return true;
        }
      }
    }
    // 2. Check if "still loading" text exists in any visible element
    const centerSpinners = Array.from(document.querySelectorAll('div, span, p')).filter(el => {
      if (el.children.length > 0) return false;
      const text = el.innerText.toLowerCase();
      if (!text.includes('still loading') && !text.includes('loading...')) return false;
      const rect = el.getBoundingClientRect();
      return rect.width > 0 && rect.height > 0 && el.style.display !== 'none';
    });
    if (centerSpinners.length > 0) return true;

    // 3. jQuery active network calls
    try {
      if (window.jQuery && typeof window.jQuery.active === 'number' && window.jQuery.active > 0) {
        return true;
      }
    } catch (_) {}

    return false;
  }

  // Helper: Wait until Odoo's network RPCs, loading overlays, and "Still loading..." are completely settled
  async function waitForOdooRpcSettled(extraDelay = 400, maxWaitMs = 12000) {
    const startTime = Date.now();
    let lastLogTime = 0;

    while (Date.now() - startTime < maxWaitMs) {
      dismissOdooModals();
      const loading = isOdooLoading();
      if (!loading) {
        break; // Langsung lanjut begitu loading screen hilang!
      }
      if (Date.now() - lastLogTime > 2000) {
        logMessage('⏳ Odoo sedang proses server (Still loading...), menunggu jaringan selesai...');
        lastLogTime = Date.now();
      }
      await sleep(150);
    }
    await sleep(extraDelay); // Jeda aman singkat 0.4s agar rendering DOM Odoo tuntas
    dismissOdooModals();
  }

  // Helper to set Odoo Many2One autocomplete dropdown with robust polling & selection
  async function setMany2OneField(fieldName, searchText, labelKeywords = [], exactMatch = false, targetMatchText = null) {
    if (!searchText) return false;
    const input = findFieldInput(fieldName, labelKeywords);
    if (!input) {
      logMessage(`Field ${fieldName} tidak ditemukan.`);
      return false;
    }

    // Dismiss any existing open menus or modals first
    dismissOdooModals();
    await waitForOdooRpcSettled(150);

    input.focus();
    input.click();
    await sleep(100);
    input.select();
    document.execCommand('selectAll', false, null);
    document.execCommand('delete', false, null);
    document.execCommand('insertText', false, searchText);
    input.value = searchText;
    input.dispatchEvent(new Event('input', { bubbles: true }));
    input.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true }));

    // Trigger jQuery UI autocomplete search directly if available
    try {
      if (window.jQuery) {
        window.jQuery(input).autocomplete('search', searchText);
      }
    } catch (_) {}

    // Poll up to 16 times (4 seconds) for autocomplete dropdown menu to appear
    let matchedItem = null;
    const searchTarget = (targetMatchText || searchText).toLowerCase().trim();
    const searchNormalized = searchTarget.replace(/\s+/g, ' ');

    for (let attempt = 0; attempt < 16; attempt++) {
      await sleep(250);
      dismissOdooModals();

      // Query ONLY visible dropdown menus currently rendered on screen using getBoundingClientRect
      const visibleMenus = Array.from(document.querySelectorAll('ul.ui-autocomplete, .o-autocomplete--dropdown-menu'))
        .filter(m => {
          const rect = m.getBoundingClientRect();
          return rect.width > 0 && rect.height > 0 && m.style.display !== 'none';
        });
      
      let options = [];
      if (visibleMenus.length > 0) {
        options = visibleMenus.flatMap(m => Array.from(m.querySelectorAll('.ui-menu-item:not(.o_m2o_dropdown_option), .dropdown-item')));
      } else {
        options = Array.from(document.querySelectorAll('.ui-autocomplete .ui-menu-item:not(.o_m2o_dropdown_option), .o-autocomplete--dropdown-menu .dropdown-item'))
          .filter(el => {
            const rect = el.getBoundingClientRect();
            return rect.width > 0 && rect.height > 0;
          });
      }

      const cleanOptions = options.filter(opt => {
        const rect = opt.getBoundingClientRect();
        if (rect.width === 0 && rect.height === 0) return false;
        const t = opt.innerText.toLowerCase().trim();
        // NEVER pick create options to prevent opening unwanted dialogs!
        return !t.startsWith('create ') && !t.startsWith('buat ') && !t.includes('search more') && !t.includes('cari lebih banyak');
      });

      if (cleanOptions.length > 0) {
        // 1. Exact match priority (normalized whitespace)
        matchedItem = cleanOptions.find(opt => {
          const optText = opt.innerText.toLowerCase().replace(/\s+/g, ' ').trim();
          return optText === searchNormalized;
        });

        // 2. Contains match if not strict exact
        if (!matchedItem && !exactMatch) {
          matchedItem = cleanOptions.find(opt => {
            const optText = opt.innerText.toLowerCase().replace(/\s+/g, ' ').trim();
            return optText.includes(searchNormalized);
          });
        }

        // 3. Match by all search tokens (e.g. "Mister Sosis" or "Joko Setiawan")
        if (!matchedItem) {
          const searchTokens = searchNormalized.split(' ').filter(t => t.length > 1);
          if (searchTokens.length > 0) {
            matchedItem = cleanOptions.find(opt => {
              const optText = opt.innerText.toLowerCase();
              return searchTokens.every(tok => optText.includes(tok));
            });
          }
        }

        // STRICT: NEVER fallback to cleanOptions[0] to prevent picking wrong records!
        if (matchedItem) break;
      }
    }

    if (matchedItem) {
      logMessage(`✓ Memilih [${fieldName}]: ${matchedItem.innerText.trim().substring(0, 35)}`);
      const link = matchedItem.querySelector('a') || matchedItem;
      link.dispatchEvent(new MouseEvent('mouseenter', { bubbles: true, view: window }));
      link.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true, view: window }));
      link.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, cancelable: true, view: window }));
      link.click();
      matchedItem.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true, view: window }));
      matchedItem.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, cancelable: true, view: window }));
      matchedItem.click();
      
      // Wait for onchange partner / analytic account RPC to settle
      await waitForOdooRpcSettled(500);
      return true;
    } else {
      // CRITICAL: NEVER press Enter! Clear value before blur to prevent opening unwanted create dialog!
      logMessage(`⚠️ Pilihan "${searchText}" tidak muncul di dropdown [${fieldName}]. Menutup dropdown agar tidak membuat record baru.`);
      input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', code: 'Escape', keyCode: 27, bubbles: true }));
      input.value = '';
      input.dispatchEvent(new Event('input', { bubbles: true }));
      if (document.activeElement && typeof document.activeElement.blur === 'function') {
        document.activeElement.blur();
      }
      await sleep(200);
      dismissOdooModals();
    }
    return false;
  }

  // Dedicated Helper to set Odoo Many2Many Tags (tag_ids: "Joko Setiawan")
  async function setTagsField(fieldName, tagText, labelKeywords = ['tags', 'tag']) {
    if (!tagText) return false;
    dismissOdooModals();

    function getTagContainer() {
      return document.querySelector(
        `div[name="${fieldName}"], [data-name="${fieldName}"], .o_field_many2manytags[name="${fieldName}"], .o_field_widget[name="${fieldName}"]`
      ) || document.querySelector('.o_field_many2manytags');
    }

    let container = getTagContainer();
    const targetNorm = tagText.toLowerCase().replace(/\s+/g, ' ').trim();
    const targetTokens = targetNorm.split(' ').filter(t => t.length > 1);

    // Helper: Purge unwanted tags (e.g. "Follow Up", "Selesai", or anything not matching target, or duplicates)
    async function purgeUnwantedTags() {
      for (let pass = 0; pass < 5; pass++) {
        const c = getTagContainer();
        if (!c) return;
        const badges = Array.from(c.querySelectorAll('.badge, .o_tag, .badge-pill, .o_badge'));
        let removedAny = false;
        let targetCount = 0;
        for (const b of badges) {
          const text = b.innerText.toLowerCase().trim();
          const isTarget = targetTokens.length > 0 && targetTokens.some(tok => text.includes(tok));
          if (!isTarget) {
            removedAny = true;
            logMessage(`🧹 Menghapus tag tidak sesuai: "${b.innerText.trim()}"...`);
            const delBtn = b.querySelector('.o_delete') || b.querySelector('.fa-times') || b.querySelector('a') || b;
            delBtn.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true, view: window }));
            delBtn.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, cancelable: true, view: window }));
            delBtn.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
            delBtn.click();
            if (window.jQuery) {
              try {
                window.jQuery(delBtn).trigger('click');
                window.jQuery(b).find('.o_delete, .fa-times').trigger('click');
              } catch (_) {}
            }
            await sleep(200);
          } else {
            targetCount++;
            if (targetCount > 1) {
              // DUPLICATE TARGET TAG: Remove extra "Joko Setiawan"!
              removedAny = true;
              logMessage(`🧹 Menghapus tag ganda: "${b.innerText.trim()}"...`);
              const delBtn = b.querySelector('.o_delete') || b.querySelector('.fa-times') || b.querySelector('a') || b;
              delBtn.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true, view: window }));
              delBtn.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, cancelable: true, view: window }));
              delBtn.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
              delBtn.click();
              if (window.jQuery) {
                try {
                  window.jQuery(delBtn).trigger('click');
                  window.jQuery(b).find('.o_delete, .fa-times').trigger('click');
                } catch (_) {}
              }
              await sleep(200);
            }
          }
        }
        if (!removedAny) break;
        await sleep(300);
        await waitForOdooRpcSettled(300);
      }
    }

    // Pre-clean: Remove any unwanted tag (e.g. Follow Up) or duplicate before starting
    await purgeUnwantedTags();

    // Check if target tag is ALREADY attached and no unwanted or duplicate tag exists
    container = getTagContainer();
    if (container) {
      const badges = Array.from(container.querySelectorAll('.badge, .o_tag, .badge-pill, .o_badge'));
      const targetMatches = badges.filter(b => targetTokens.some(tok => b.innerText.toLowerCase().includes(tok)));
      if (targetMatches.length === 1 && badges.length === 1) {
        logMessage(`✓ Tag [${tagText}] sudah sesuai (1 tag).`);
        return true;
      }
      if (targetMatches.length > 0) {
        await purgeUnwantedTags();
        const freshBadges = Array.from(getTagContainer()?.querySelectorAll('.badge, .o_tag, .badge-pill, .o_badge') || []);
        const freshMatches = freshBadges.filter(b => targetTokens.some(tok => b.innerText.toLowerCase().includes(tok)));
        if (freshMatches.length === 1 && freshBadges.length === 1) {
          logMessage(`✓ Tag [${tagText}] sudah sesuai (1 tag).`);
          return true;
        }
      }
    }

    // 2. Search strategies: try short keyword "Joko" first (most reliable in Odoo M2M), fallback to full name
    const searchKeywords = ['Joko', tagText];
    let matchedOption = null;

    for (const kw of searchKeywords) {
      if (matchedOption) break;
      dismissOdooModals();

      // Always query fresh live input element from tags container
      const liveInput = getTagContainer()?.querySelector('input') || findFieldInput(fieldName, labelKeywords);
      if (!liveInput) {
        logMessage(`Input field [${fieldName}] tidak ditemukan.`);
        return false;
      }

      liveInput.focus();
      liveInput.click();
      await sleep(100);

      // Type keyword with select & insertText
      try {
        liveInput.select();
        document.execCommand('selectAll', false, null);
        document.execCommand('delete', false, null);
        document.execCommand('insertText', false, kw);
      } catch (_) {}
      liveInput.value = kw;
      liveInput.dispatchEvent(new Event('input', { bubbles: true }));
      liveInput.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true }));

      // Explicitly trigger jQuery UI autocomplete search
      try {
        if (window.jQuery && typeof window.jQuery(liveInput).autocomplete === 'function') {
          window.jQuery(liveInput).autocomplete('search', kw);
        }
      } catch (_) {}

      // Poll for autocomplete dropdown
      for (let attempt = 0; attempt < 18; attempt++) {
        await sleep(200);
        dismissOdooModals();

        // Find visible menus using getBoundingClientRect
        const visibleMenus = Array.from(document.querySelectorAll('ul.ui-autocomplete, .o-autocomplete--dropdown-menu'))
          .filter(m => {
            const rect = m.getBoundingClientRect();
            return rect.width > 0 && rect.height > 0 && m.style.display !== 'none';
          });

        let menuOptions = [];
        if (visibleMenus.length > 0) {
          menuOptions = visibleMenus.flatMap(m => Array.from(m.querySelectorAll('.ui-menu-item, .dropdown-item')));
        } else {
          menuOptions = Array.from(document.querySelectorAll('.ui-autocomplete .ui-menu-item, .o-autocomplete--dropdown-menu .dropdown-item'))
            .filter(el => {
              const rect = el.getBoundingClientRect();
              return rect.width > 0 && rect.height > 0;
            });
        }

        const validOptions = menuOptions.filter(opt => {
          const rect = opt.getBoundingClientRect();
          if (rect.width === 0 && rect.height === 0) return false;
          const t = opt.innerText.toLowerCase().trim();
          return !t.startsWith('create ') && !t.startsWith('buat ') && !t.includes('search more') && !t.includes('cari lebih banyak');
        });

        if (validOptions.length > 0) {
          // Priority 1: Exact match
          matchedOption = validOptions.find(opt => {
            const optNorm = opt.innerText.toLowerCase().replace(/\s+/g, ' ').trim();
            return optNorm === targetNorm;
          });

          // Priority 2: Contains both "joko" and "setiawan"
          if (!matchedOption) {
            matchedOption = validOptions.find(opt => {
              const optNorm = opt.innerText.toLowerCase().replace(/\s+/g, ' ').trim();
              return optNorm.includes(targetNorm) || (optNorm.includes('joko') && optNorm.includes('setiawan'));
            });
          }

          if (matchedOption) break;
        }
      }
    }

    const currentLiveInput = getTagContainer()?.querySelector('input') || findFieldInput(fieldName, labelKeywords);

    if (matchedOption) {
      logMessage(`✓ Memilih Tag: "${matchedOption.innerText.trim()}"`);
      const clickEl = matchedOption.querySelector('a') || matchedOption;
      clickEl.dispatchEvent(new MouseEvent('mouseenter', { bubbles: true, view: window }));
      clickEl.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true, view: window }));
      clickEl.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, cancelable: true, view: window }));
      clickEl.click();
      matchedOption.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true, view: window }));
      matchedOption.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, cancelable: true, view: window }));
      matchedOption.click();

      // Trigger jQuery UI autocompleteselect on live input
      try {
        if (window.jQuery && currentLiveInput) {
          const itemData = window.jQuery(matchedOption).data('ui-autocomplete-item')
                        || window.jQuery(matchedOption).data('item.autocomplete')
                        || window.jQuery(clickEl).data('ui-autocomplete-item');
          if (itemData) {
            window.jQuery(currentLiveInput).trigger(window.jQuery.Event('autocompleteselect', { item: itemData }));
          }
        }
      } catch (_) {}

      await sleep(350);
      await waitForOdooRpcSettled(400);

      // Post-clean to guarantee strictly ONE "Joko Setiawan" tag remains and unwanted tags are gone
      await purgeUnwantedTags();

      // Final check
      const postContainer = getTagContainer();
      if (postContainer) {
        const badges = Array.from(postContainer.querySelectorAll('.badge, .o_tag, .badge-pill, .o_badge'));
        if (badges.some(b => b.innerText.toLowerCase().includes('joko'))) {
          logMessage(`✓ Berhasil memasang Tag "${tagText}"!`, true);
          return true;
        }
      }
      return true;
    } else {
      logMessage(`⚠️ Tag "${tagText}" tidak ditemukan di dropdown autocomplete. Menutup dropdown.`);
      if (currentLiveInput) {
        currentLiveInput.value = '';
        currentLiveInput.dispatchEvent(new Event('input', { bubbles: true }));
        currentLiveInput.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', code: 'Escape', keyCode: 27, bubbles: true }));
      }
      if (document.activeElement && typeof document.activeElement.blur === 'function') {
        document.activeElement.blur();
      }
      await sleep(200);
      dismissOdooModals();
      await purgeUnwantedTags();
      return false;
    }
  }

  // Helper to set plain text field
  function setTextField(fieldName, value) {
    if (!value) return false;
    const input = findFieldInput(fieldName);
    if (!input) return false;
    input.focus();
    input.value = value;
    triggerEvents(input);
    return true;
  }

  // Helper to click tab
  function clickTab(tabText) {
    const tabs = Array.from(document.querySelectorAll('.nav-tabs a, .nav-link, [role="tab"], .o_notebook_headers a, .o_notebook_headers li a'));
    const matched = tabs.find(t => t.innerText.trim().toLowerCase().includes(tabText.toLowerCase()));
    if (matched) {
      matched.click();
      return true;
    }
    return false;
  }

  // Helper to set "Deliver To" in PT PO (Other Information -> picking_type_id)
  async function setDeliverToField() {
    logMessage('2. Mengatur Deliver To di tab Other Information...');
    clickTab('Other Information');
    await sleep(350);
    await waitForOdooRpcSettled(300);

    const container = document.querySelector('div[name="picking_type_id"], [data-name="picking_type_id"], .o_field_widget[name="picking_type_id"]');
    let input = (container && container.querySelector('input')) || findFieldInput('picking_type_id', ['deliver to', 'kirim ke']);
    if (!input) {
      logMessage('⚠️ Field Deliver To (picking_type_id) tidak ditemukan.');
      clickTab('Products');
      return false;
    }

    dismissOdooModals();

    // 1. Check if ALREADY set to Jawa Tengah
    if (input.value && input.value.toLowerCase().includes('jawa tengah')) {
      logMessage(`✓ Deliver To sudah Jawa Tengah: "${input.value.trim()}"`);
      clickTab('Products');
      await sleep(300);
      return true;
    }

    // Helper to get clean dropdown options
    function getCleanDropdownOptions() {
      const visibleMenus = Array.from(document.querySelectorAll('ul.ui-autocomplete, .o-autocomplete--dropdown-menu, .dropdown-menu'))
        .filter(m => {
          const rect = m.getBoundingClientRect();
          return rect.width > 0 && rect.height > 0 && m.style.display !== 'none';
        });
      let menuOptions = [];
      if (visibleMenus.length > 0) {
        menuOptions = visibleMenus.flatMap(m => Array.from(m.querySelectorAll('.ui-menu-item, .dropdown-item, li.ui-menu-item')));
      } else {
        menuOptions = Array.from(document.querySelectorAll('.ui-autocomplete .ui-menu-item, .o-autocomplete--dropdown-menu .dropdown-item, li.ui-menu-item'))
          .filter(el => {
            const rect = el.getBoundingClientRect();
            return rect.width > 0 && rect.height > 0;
          });
      }
      return menuOptions.filter(opt => {
        const rect = opt.getBoundingClientRect();
        if (rect.width === 0 && rect.height === 0) return false;
        const t = opt.innerText.toLowerCase().trim();
        return !t.startsWith('create ') && !t.startsWith('buat ') && !t.includes('search more') && !t.includes('cari lebih banyak');
      });
    }

    // 2. Open dropdown by clicking caret button or input
    const dropBtn = container?.querySelector('.o_dropdown_button, button, .fa-caret-down');
    if (dropBtn) {
      dropBtn.dispatchEvent(new MouseEvent('mousedown', { bubbles: true }));
      dropBtn.dispatchEvent(new MouseEvent('mouseup', { bubbles: true }));
      dropBtn.click();
    } else {
      input.focus();
      input.click();
    }
    await sleep(250);

    let cleanOptions = [];
    for (let wait = 0; wait < 10; wait++) {
      await sleep(200);
      cleanOptions = getCleanDropdownOptions();
      if (cleanOptions.length > 0) break;
    }

    // 3. If options didn't appear by clicking caret, type 'Jawa Tengah' directly
    if (cleanOptions.length === 0) {
      input.focus();
      input.select();
      document.execCommand('selectAll', false, null);
      document.execCommand('delete', false, null);
      document.execCommand('insertText', false, 'Jawa Tengah');
      input.value = 'Jawa Tengah';
      input.dispatchEvent(new Event('input', { bubbles: true }));
      input.dispatchEvent(new KeyboardEvent('keyup', { key: 'h', bubbles: true }));

      for (let wait = 0; wait < 12; wait++) {
        await sleep(200);
        cleanOptions = getCleanDropdownOptions();
        if (cleanOptions.length > 0) break;
      }
    }

    if (cleanOptions.length > 0) {
      const optionTexts = cleanOptions.map(opt => opt.innerText.trim());
      logMessage(`ℹ️ Pilihan Deliver To: [${optionTexts.join(' | ')}]`);

      // Priority 1: Contains "jawa" and "tengah" (or "jateng")
      let matched = cleanOptions.find(opt => {
        const t = opt.innerText.toLowerCase();
        return (t.includes('jawa') && t.includes('tengah')) || t.includes('jateng');
      });

      // Priority 2: Contains "receipt" or "penerimaan"
      if (!matched) {
        matched = cleanOptions.find(opt => {
          const t = opt.innerText.toLowerCase();
          return t.includes('receipt') || t.includes('penerimaan');
        });
      }

      if (matched) {
        logMessage(`✓ Memilih Deliver To: "${matched.innerText.trim()}"`);
        const link = matched.querySelector('a') || matched;
        link.dispatchEvent(new MouseEvent('mouseenter', { bubbles: true, view: window }));
        link.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true, view: window }));
        link.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, cancelable: true, view: window }));
        link.click();
        matched.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true, view: window }));
        matched.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, cancelable: true, view: window }));
        matched.click();

        await sleep(350);
        await waitForOdooRpcSettled(400);

        clickTab('Products');
        await sleep(350);
        await waitForOdooRpcSettled(300);
        return true;
      }
    }

    logMessage('⚠️ Tidak dapat menemukan pilihan yang cocok untuk Deliver To.');
    clickTab('Products');
    await sleep(350);
    return false;
  }

  // MAIN AUTO-FILL FUNCTION
  async function runAutoFill(mode) {
    // 1. Coba update data dari clipboard
    await pasteFromClipboard(false);

    if (!currentPayload || !currentPayload.items || currentPayload.items.length === 0) {
      const pasted = prompt('Data invoice belum terhubung.\nSilakan tekan Ctrl+V (Paste) di bawah ini lalu klik OK:');
      if (pasted && applyPayloadText(pasted, true)) {
        // Berhasil dimuat dari prompt paste! Lanjutkan otomatis
      } else {
        logMessage('Peringatan: Belum ada data invoice yang siap!', false, true);
        return;
      }
    }

    const p = currentPayload;
    logMessage(`Memulai Auto-Fill ${mode} untuk Invoice #${p.invoiceNo}...`);

    try {
      if (mode === 'PT_PO') {
        // PT PO: Requests for Quotation (Purchase)
        logMessage('1. Mengisi Vendor & Vendor Reference...');
        await setMany2OneField('partner_id', 'CV Fivafood and Meat Supply', ['vendor', 'rekanan']);
        setTextField('partner_ref', p.vendorRef || `${p.customerAlias || p.customerName} ${p.city}`);
        await setMany2OneField('currency_id', 'IDP', ['currency', 'mata uang']);

        // 2. Deliver To in Other Information tab
        await setDeliverToField();

        logMessage('3. Membuka tab Products...');
        clickTab('Products');
        await sleep(300);

        // Fill Items
        const filled = await fillOrderLines(p.items, 'PT_PO');
        if (filled === p.items.length) {
          logMessage(`🎉 SELESAI! Semua baris (${filled}/${p.items.length}) terisi (Draft). Silakan periksa angka lalu klik SAVE.`, true);
        } else {
          logMessage(`⚠️ Baru terisi ${filled} dari ${p.items.length} baris (terkendala loading Odoo). Silakan klik Auto-Fill kembali untuk melanjutkan baris sisanya.`, false, true);
        }

      } else if (mode === 'PT_SO') {
        // PT SO: Quotation (Sales PT)
        logMessage('1. Mengisi Customer PT SO...');
        await setMany2OneField('partner_id', p.ptSoCustomer || `${p.customerAlias} (${p.customerName})`, ['customer', 'pelanggan']);
        await setMany2OneField('pricelist_id', 'PFS Customer (IDP)', ['pricelist', 'daftar harga']);

        // 2. Tab Other Info: Tags -> "Joko Setiawan" & Analytic Account -> "PFS-Jateng"
        logMessage('2. Membuka tab Other Info...');
        clickTab('Other Info');
        await sleep(300);
        await waitForOdooRpcSettled(300);

        // Tags -> "Joko Setiawan"
        logMessage('3. Mengisi Tags: "Joko Setiawan"...');
        await setTagsField('tag_ids', 'Joko Setiawan', ['tags', 'tag']);
        await waitForOdooRpcSettled(400);

        // Analytic Account -> "PFS-Jateng"
        logMessage('4. Mengisi Analytic Account: "PFS-Jateng"...');
        await setMany2OneField(
          'analytic_account_id',
          'PFS-Jateng',
          ['analytic account', 'akun analitis']
        );
        await waitForOdooRpcSettled(400);

        // 3. Kembali ke Order Lines
        logMessage('5. Membuka tab Order Lines (Harga sebelum PPN, Diskon Invoice, Taxes 11%)...');
        clickTab('Order Lines');
        await sleep(300);
        await waitForOdooRpcSettled(300);

        // 4. Fill Items
        const filled = await fillOrderLines(p.items, 'PT_SO');
        if (filled === p.items.length) {
          logMessage(`🎉 SELESAI! Semua baris (${filled}/${p.items.length}) terisi (Draft). Silakan periksa angka lalu klik SAVE.`, true);
        } else {
          logMessage(`⚠️ Baru terisi ${filled} dari ${p.items.length} baris (terkendala loading Odoo). Silakan klik Auto-Fill kembali untuk melanjutkan baris sisanya.`, false, true);
        }

      } else if (mode === 'CV_SO') {
        // CV SO: Quotation (Sales CV)
        logMessage('1. Mengisi Customer: PT Putra Fiva Sejahtera ( JAWA TENGAH )...');
        await setMany2OneField(
          'partner_id',
          'PT Putra Fiva Sejahtera ( JAWA TENGAH )',
          ['customer', 'pelanggan']
        );
        logMessage('⏳ Menunggu Odoo memuat default alamat & pricelist...');
        await waitForOdooRpcSettled(500);

        // 2. Delivery Address: cari Customer (misal MISTER SOSIS) via dropdown
        const deliveryTarget = p.cvSoDelivery || p.customerAlias || p.customerName;
        if (deliveryTarget) {
          logMessage(`2. Mengisi Delivery Address: "${deliveryTarget}" via dropdown...`);
          await setMany2OneField(
            'partner_shipping_id',
            deliveryTarget,
            ['delivery address', 'alamat pengiriman']
          );
          await waitForOdooRpcSettled(400);
        }

        // 3. Masuk ke tab "Other Info"
        logMessage('3. Membuka tab Other Info...');
        clickTab('Other Info');
        await sleep(300);
        await waitForOdooRpcSettled(300);

        // 4. Kolom Tag -> dropdown pilih "Joko Setiawan"
        logMessage('4. Mengisi Tags: "Joko Setiawan"...');
        await setTagsField('tag_ids', 'Joko Setiawan', ['tags', 'tag']);
        await waitForOdooRpcSettled(400);

        // 5. Kolom Analytic Account -> dropdown pilih "Jateng"
        logMessage('5. Mengisi Analytic Account: "Jateng"...');
        await setMany2OneField(
          'analytic_account_id',
          'Jateng',
          ['analytic account', 'akun analitis']
        );
        await waitForOdooRpcSettled(400);

        // 6. Kembali ke tab "Order Lines"
        logMessage('6. Membuka tab Order Lines...');
        clickTab('Order Lines');
        await sleep(300);
        await waitForOdooRpcSettled(300);

        // 7. Mengisi Produk / Item Barang (Wajib PRODUK LK, Dilarang PRODUK JADI)
        logMessage('7. Mengisi item produk CV SO (Harga PO/SO & [PRODUK LK])...');
        const filled = await fillOrderLines(p.items, 'CV_SO');
        if (filled === p.items.length) {
          logMessage(`🎉 SELESAI! Semua baris (${filled}/${p.items.length}) terisi (Draft). Silakan periksa angka lalu klik SAVE.`, true);
        } else {
          logMessage(`⚠️ Baru terisi ${filled} dari ${p.items.length} baris (terkendala loading Odoo). Silakan klik Auto-Fill kembali untuk melanjutkan baris sisanya.`, false, true);
        }
      }

    } catch (err) {
      console.error('[Lucifax-Odoo] Error during auto-fill:', err);
      logMessage(`Error: ${err.message}`, false, true);
    }
  }

  // Timing settings based on user-selected speed in widget
  function getTimingSettings() {
    const speed = document.getElementById('lucifax-speed-select')?.value || 'safe';
    if (speed === 'ultra_safe') {
      return {
        name: 'Sangat Santai',
        delayAfterRow: 2000,
        delayAfterProduct: 2800,
        delayCellInput: 1100,
        delayAfterRowCommit: 1800,
        retries: 5,
      };
    } else if (speed === 'fast') {
      return {
        name: 'Cepat',
        delayAfterRow: 800,
        delayAfterProduct: 1400,
        delayCellInput: 500,
        delayAfterRowCommit: 800,
        retries: 3,
      };
    } else {
      // Default: 'safe' (Mode Aman / Jaringan Lambat)
      return {
        name: 'Aman (Rekomendasi)',
        delayAfterRow: 1400,
        delayAfterProduct: 2200,
        delayCellInput: 800,
        delayAfterRowCommit: 1400,
        retries: 4,
      };
    }
  }

  // Find cell by column header name or data-name in table
  function findCellByColumnHeader(row, headerKeywords, fieldName) {
    if (!row) return null;
    const table = row.closest('table') || document.querySelector('table.o_section_and_note_list_view, table.o_list_table, .o_field_x2many_list table');
    if (!table) return null;
    const headers = Array.from(table.querySelectorAll('thead th'));
    let colIndex = -1;
    if (fieldName) {
      colIndex = headers.findIndex(th => 
        th.getAttribute('data-name') === fieldName || 
        th.getAttribute('name') === fieldName ||
        th.classList.contains(fieldName)
      );
    }
    if (colIndex === -1 && headerKeywords) {
      colIndex = headers.findIndex(th => {
        const text = th.innerText.toLowerCase();
        return headerKeywords.some(kw => text.includes(kw.toLowerCase()));
      });
    }
    if (colIndex !== -1) {
      const cells = row.querySelectorAll('td');
      return cells[colIndex] || null;
    }
    return null;
  }

  // Helper: Query all order line rows (both view mode and edit mode)
  function getOrderLineRows() {
    return Array.from(document.querySelectorAll('table.o_section_and_note_list_view tbody tr, tbody tr'))
      .filter(r => {
        if (r.classList.contains('o_field_x2many_list_row_add')) return false;
        if (r.classList.contains('o_data_row') || r.classList.contains('o_selected_row')) return true;
        if (r.querySelector('td[name="product_id"], td[data-name="product_id"], td.o_data_cell')) return true;
        return false;
      });
  }

  // Helper: Add new row and VERIFY it appears before proceeding
  async function addNewRowWithVerification(targetIndex, timing) {
    for (let attempt = 1; attempt <= timing.retries; attempt++) {
      dismissDiscardModal();
      // Wait for any pending Odoo loading / tax RPC to finish first!
      await waitForOdooRpcSettled(300);

      let currentRows = getOrderLineRows();
      if (currentRows.length > targetIndex) {
        return currentRows[targetIndex];
      }

      // Blur previous element so Odoo commits previous cell
      if (document.activeElement && typeof document.activeElement.blur === 'function') {
        document.activeElement.blur();
      }
      await sleep(200);
      await waitForOdooRpcSettled(300);

      const addBtns = Array.from(document.querySelectorAll('.o_field_x2many_list_row_add a, button.o_field_x2many_list_row_add, .o_field_widget a, a.o_field_x2many_list_row_add'));
      const addBtn = addBtns.find(b => b.innerText.toLowerCase().includes('add a product') || b.innerText.toLowerCase().includes('tambah produk'));
      if (!addBtn) {
        logMessage('⚠️ Tombol "Add a product" tidak ditemukan!');
        return null;
      }

      // Click cleanly without URL hash navigation
      addBtn.focus();
      addBtn.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true }));
      addBtn.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, cancelable: true }));
      addBtn.click();

      // Poll up to 16 times (4s) for new row to appear
      for (let wait = 0; wait < 16; wait++) {
        await sleep(250);
        dismissDiscardModal();
        currentRows = getOrderLineRows();
        if (currentRows.length > targetIndex) {
          await sleep(timing.delayAfterRow);
          return currentRows[targetIndex];
        }
      }

      logMessage(`⏳ Menunggu Odoo menyiapkan baris #${targetIndex + 1} (percobaan ${attempt}/${timing.retries})...`);
    }
    return null;
  }

  // Helper: Wait for Odoo's onchange_product_id network RPC to finish and populate the row
  async function waitForProductOnchange(rowIndex, expectedTokens, timing) {
    const startTime = Date.now();
    const maxWaitMs = 6000;
    while (Date.now() - startTime < maxWaitMs) {
      dismissDiscardModal();
      const rows = getOrderLineRows();
      const row = rows[rowIndex];
      if (row) {
        const descCell = row.querySelector('td[name="name"]') || findCellByColumnHeader(row, ['description', 'deskripsi']);
        const uomCell = row.querySelector('td[name="product_uom"], td[name="product_uom_id"]') || findCellByColumnHeader(row, ['uom', 'satuan']);
        const descText = (descCell?.innerText || '').toLowerCase();
        const uomText = (uomCell?.innerText || '').toLowerCase();

        // Odoo onchange is done when Description or UoM has content
        const hasContent = descText.length > 2 || uomText.length > 0;
        const isLoading = document.querySelector('.o_loading:not(.d-none), .o_blockUI');

        if (hasContent && !isLoading) {
          await sleep(timing.delayAfterProduct);
          return true;
        }
      }
      await sleep(250);
    }
    // Fallback safe buffer
    await sleep(timing.delayAfterProduct);
    return false;
  }

  // Helper: Safely set cell input and VERIFY that the value is stored before proceeding
  async function setAndVerifyCell(rowIndex, cellSelector, headerKeywords, value, colName, timing) {
    if (value === undefined || value === null) return false;

    const formattedVal = typeof value === 'number'
      ? (value % 1 === 0 ? Math.round(value).toString() : Number(value.toFixed(2)).toString())
      : value.toString();
    const cleanTarget = formattedVal.replace(/[.,\s%]/g, '');
    const targetNum = typeof value === 'number' ? value : parseFloat(formattedVal.replace(',', '.'));
    const isNumeric = !isNaN(targetNum);

    function checkCellMatches(raw) {
      if (!raw) return false;
      const clean = raw.trim().replace(/[.,\s%]/g, '');
      if (clean === cleanTarget || clean.includes(cleanTarget) || cleanTarget.includes(clean)) return true;
      if (isNumeric) {
        const numPart = raw.replace(/[^0-9.,]/g, '');
        if (numPart) {
          const parsed = parseFloat(numPart.replace(/,/g, ''));
          if (!isNaN(parsed) && Math.abs(parsed - targetNum) < 0.05) return true;
          const parsedId = parseFloat(numPart.replace(/\./g, '').replace(',', '.'));
          if (!isNaN(parsedId) && Math.abs(parsedId - targetNum) < 0.05) return true;
        }
      }
      return false;
    }

    for (let attempt = 1; attempt <= timing.retries; attempt++) {
      dismissDiscardModal();

      // ALWAYS query fresh row from DOM to prevent detached node reference
      const rows = getOrderLineRows();
      const row = rows[rowIndex];
      if (!row) {
        await sleep(300);
        continue;
      }

      const fieldMatch = cellSelector.match(/name="([^"]+)"/);
      const fieldName = fieldMatch ? fieldMatch[1] : null;
      let cell = row.querySelector(cellSelector) || findCellByColumnHeader(row, headerKeywords, fieldName);
      if (!cell) {
        await sleep(300);
        continue;
      }

      // Check if already contains the target value
      const currentRaw = (cell.querySelector('input')?.value || cell.innerText || '').trim();
      if (checkCellMatches(currentRaw)) {
        logMessage(`✓ Kolom ${colName} [${formattedVal}] terverifikasi`);
        return true;
      }

      // Activate cell
      cell.click();
      await sleep(200);

      let input = cell.querySelector('input');
      if (!input) {
        cell.dispatchEvent(new MouseEvent('dblclick', { bubbles: true }));
        await sleep(200);
        input = cell.querySelector('input');
      }

      if (input && (input.tagName === 'INPUT' || input.tagName === 'TEXTAREA')) {
        input.focus();
        input.select();
        document.execCommand('selectAll', false, null);
        document.execCommand('delete', false, null);
        document.execCommand('insertText', false, formattedVal);
        input.value = formattedVal;
        input.dispatchEvent(new Event('input', { bubbles: true }));
        input.dispatchEvent(new Event('change', { bubbles: true }));
        input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Tab', code: 'Tab', keyCode: 9, bubbles: true }));
        input.dispatchEvent(new Event('blur', { bubbles: true }));
      }

      // Wait for Odoo to compute/accept cell input
      await sleep(timing.delayCellInput);
      dismissDiscardModal();

      // Read back from live DOM to VERIFY
      const freshRows = getOrderLineRows();
      const freshRow = freshRows[rowIndex];
      const freshCell = freshRow ? (freshRow.querySelector(cellSelector) || findCellByColumnHeader(freshRow, headerKeywords, fieldName)) : null;
      const verifiedRaw = (freshCell?.querySelector('input')?.value || freshCell?.innerText || '').trim();

      if (checkCellMatches(verifiedRaw)) {
        logMessage(`✓ Kolom ${colName} [${formattedVal}] tersimpan`);
        return true;
      }

      logMessage(`⏳ Verifikasi ${colName} [${formattedVal}] belum terbaca (coba lagi ${attempt}/${timing.retries})...`);
      await sleep(350);
    }

    logMessage(`⚠️ Kolom ${colName} selesai diatur ke ${formattedVal}`);
    return false;
  }

  // Helper: Set Taxes field (in PT PO & PT SO, Taxes always = 11%)
  async function setTaxesField(rowIndex, timing, taxTarget = '11%') {
    // 1. First check if cell already has 11% tag BEFORE doing any click
    const initialRows = getOrderLineRows();
    const initialRow = initialRows[rowIndex];
    if (initialRow) {
      const initialCell = initialRow.querySelector('td[name="tax_id"], td[name="taxes_id"], td[data-name="tax_id"], td[data-name="taxes_id"]') 
        || findCellByColumnHeader(initialRow, ['taxes', 'pajak'], 'tax_id')
        || findCellByColumnHeader(initialRow, ['taxes', 'pajak'], 'taxes_id');
      const hasTax = initialCell && (
        initialCell.innerText.includes(taxTarget) || 
        Array.from(initialCell.querySelectorAll('.badge, .o_tag, .badge-pill, .o_badge')).some(b => b.innerText.includes(taxTarget))
      );
      if (hasTax) {
        logMessage(`✓ Taxes sudah ${taxTarget}`);
        return true;
      }
    }

    for (let attempt = 1; attempt <= timing.retries; attempt++) {
      dismissDiscardModal();
      await waitForOdooRpcSettled(200);

      const rows = getOrderLineRows();
      const row = rows[rowIndex];
      if (!row) {
        await sleep(250);
        continue;
      }

      // Find Taxes cell
      let cell = row.querySelector('td[name="tax_id"], td[name="taxes_id"], td[data-name="tax_id"], td[data-name="taxes_id"]') 
        || findCellByColumnHeader(row, ['taxes', 'pajak'], 'tax_id')
        || findCellByColumnHeader(row, ['taxes', 'pajak'], 'taxes_id');
      if (!cell) {
        await sleep(250);
        continue;
      }

      // Check again if tag was already added
      const existingTags = Array.from(cell.querySelectorAll('.badge, .o_tag, .badge-pill, .o_badge'));
      if (cell.innerText.includes(taxTarget) || existingTags.some(b => b.innerText.includes(taxTarget))) {
        logMessage(`✓ Taxes terverifikasi: ${taxTarget}`);
        return true;
      }

      // 2. Click cell to open input / tag editor
      cell.click();
      await sleep(200);

      let input = cell.querySelector('input');
      if (!input) {
        cell.dispatchEvent(new MouseEvent('dblclick', { bubbles: true }));
        await sleep(200);
        input = cell.querySelector('input');
      }

      if (input && (input.tagName === 'INPUT' || input.tagName === 'TEXTAREA')) {
        input.focus();
        document.execCommand('selectAll', false, null);
        document.execCommand('delete', false, null);
        document.execCommand('insertText', false, taxTarget);
        input.value = taxTarget;
        input.dispatchEvent(new Event('input', { bubbles: true }));
        input.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true }));

        // Check dropdown options with polling
        let taxOption = null;
        for (let wait = 0; wait < 10; wait++) {
          await sleep(200);
          dismissDiscardModal();
          const dropdownOptions = Array.from(document.querySelectorAll('.ui-autocomplete .ui-menu-item, .o-autocomplete--dropdown-menu .dropdown-item'));
          taxOption = dropdownOptions.find(opt => {
            const rect = opt.getBoundingClientRect();
            if (rect.width === 0 && rect.height === 0) return false;
            return opt.innerText.trim().includes(taxTarget) || opt.innerText.trim().includes('11');
          });
          if (taxOption) break;
        }

        if (taxOption) {
          const link = taxOption.querySelector('a') || taxOption;
          link.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true, view: window }));
          link.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, cancelable: true, view: window }));
          link.click();
          
          // CRITICAL: Wait for Odoo's onchange_taxes RPC and loading overlay to finish!
          logMessage(`⏳ Menunggu perhitungan PPN 11% Odoo selesai...`);
          await waitForOdooRpcSettled(timing.delayAfterProduct);
          return true;
        } else {
          input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', code: 'Escape', keyCode: 27, bubbles: true }));
          if (document.activeElement && typeof document.activeElement.blur === 'function') {
            document.activeElement.blur();
          }
          await sleep(200);
        }
      }

      // Verify cell content
      const freshRows = getOrderLineRows();
      const freshRow = freshRows[rowIndex];
      const freshCell = freshRow ? (freshRow.querySelector('td[name="tax_id"], td[name="taxes_id"], td[data-name="tax_id"], td[data-name="taxes_id"]') || findCellByColumnHeader(freshRow, ['taxes', 'pajak'], 'tax_id') || findCellByColumnHeader(freshRow, ['taxes', 'pajak'], 'taxes_id')) : null;
      if (freshCell && (freshCell.innerText.includes(taxTarget) || Array.from(freshCell.querySelectorAll('.badge, .o_tag')).some(b => b.innerText.includes(taxTarget)))) {
        logMessage(`✓ Taxes terverifikasi: ${taxTarget}`);
        return true;
      }

      await sleep(300);
    }
    return false;
  }

  // Helper: Clear Taxes field (in PT SO & CV SO, Taxes must be empty!)
  async function clearTaxesField(rowIndex, timing) {
    for (let attempt = 1; attempt <= timing.retries; attempt++) {
      dismissDiscardModal();
      await waitForOdooRpcSettled(200);

      const rows = getOrderLineRows();
      const row = rows[rowIndex];
      if (!row) {
        await sleep(250);
        continue;
      }

      // Find Taxes cell (in Sales it is name="tax_id", in Purchase it is name="taxes_id")
      let cell = row.querySelector('td[name="tax_id"], td[name="taxes_id"], td[data-name="tax_id"], td[data-name="taxes_id"]') 
        || findCellByColumnHeader(row, ['taxes', 'pajak'], 'tax_id')
        || findCellByColumnHeader(row, ['taxes', 'pajak'], 'taxes_id');
      if (!cell) {
        await sleep(250);
        continue;
      }

      // 1. Check if already empty
      const badges = Array.from(cell.querySelectorAll('.badge, .o_tag, .badge-pill, .o_badge'));
      const textHasTax = cell.innerText.includes('%') || cell.innerText.toLowerCase().includes('tax');
      if (badges.length === 0 && !textHasTax) {
        logMessage(`✓ Taxes baris ${rowIndex + 1} sudah kosong`);
        return true;
      }

      // 2. Click all delete buttons (x) on badges
      let clickedAny = false;
      for (const b of badges) {
        const delBtn = b.querySelector('.o_delete, .fa-times, .close, a, i') || b;
        delBtn.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true, view: window }));
        delBtn.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, cancelable: true, view: window }));
        delBtn.click();
        clickedAny = true;
        await sleep(150);
      }

      // 3. If badges still remain, activate cell to open tag editor
      const remainingBeforeEdit = Array.from(cell.querySelectorAll('.badge, .o_tag'));
      if (remainingBeforeEdit.length > 0) {
        cell.click();
        await sleep(200);

        // Click delete buttons inside activated cell
        const editDelBtns = Array.from(cell.querySelectorAll('.o_delete, .fa-times, .close, a, i'));
        for (const db of editDelBtns) {
          db.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true, view: window }));
          db.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, cancelable: true, view: window }));
          db.click();
          await sleep(150);
        }

        // If input field is present, select and clear / backspace
        const input = cell.querySelector('input');
        if (input) {
          input.focus();
          input.value = '';
          input.dispatchEvent(new Event('input', { bubbles: true }));
          input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Backspace', code: 'Backspace', keyCode: 8, bubbles: true }));
          await sleep(100);
          input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', code: 'Escape', keyCode: 27, bubbles: true }));
          if (document.activeElement && typeof document.activeElement.blur === 'function') {
            document.activeElement.blur();
          }
        }
      }

      // Wait for Odoo onchange
      await waitForOdooRpcSettled(timing.delayCellInput || 500);
      dismissDiscardModal();

      // Read back to verify
      const freshRows = getOrderLineRows();
      const freshRow = freshRows[rowIndex];
      const freshCell = freshRow ? (freshRow.querySelector('td[name="tax_id"], td[name="taxes_id"]') || findCellByColumnHeader(freshRow, ['taxes', 'pajak'])) : null;
      const freshBadges = freshCell ? Array.from(freshCell.querySelectorAll('.badge, .o_tag')) : [];
      if (freshBadges.length === 0 && (!freshCell || !freshCell.innerText.includes('%'))) {
        logMessage(`✓ Taxes baris ${rowIndex + 1} bersih (tanpa PPN)`);
        return true;
      }

      await sleep(300);
    }
    return false;
  }

  // Fill product order lines in Odoo table with strict step-by-step verification
  async function fillOrderLines(items, mode) {
    const timing = getTimingSettings();
    const isPtPo = (mode === 'PT_PO');
    const isCvSo = (mode === 'CV_SO');
    let successfulRows = 0;
    logMessage(`⚙️ Menggunakan ${timing.name} (Verifikasi ketat per kolom)...`);

    for (let i = 0; i < items.length; i++) {
      dismissOdooModals();

      const item = items[i];
      // Full registered name from Master Barang (e.g. [PRODUK LK] BRS 13 PCS 500 g LK)
      const registeredOdooName = (item.odooProductName && item.odooProductName.trim().length > 0)
        ? item.odooProductName.trim()
        : '';
      const fallbackName = (item.productName && item.productName.trim().length > 0)
        ? item.productName.trim()
        : '';
      const exactOdooName = registeredOdooName || fallbackName;

      // Quantity in Odoo is always QTY (Packs/Pieces), NOT Karton!
      const qty = (item.quantityPack !== undefined && item.quantityPack !== null)
        ? item.quantityPack
        : ((item.qty !== undefined && item.qty !== null) ? item.qty : item.quantityCarton);
      
      // Determine unit price based on mode
      let price = item.pricePoSo || item.priceUnit;
      if (mode === 'PT_SO') {
        price = item.priceSalePrePpn || (item.priceUnit / 1.11);
      }

      // Clean name to type: strip leading [bracket] prefix (e.g. "[PRODUK LK] BRS Merah 24 PCS @ 500 g LK" -> "BRS Merah 24 PCS @ 500 g LK")
      const exactCleanName = exactOdooName.replace(/^\[.*?\]\s*/, '').replace(/\s+/g, ' ').trim();

      // Extract core query tokens for intelligent fallback (e.g. "BRS Merah 24", "BRS 13", "BRS ORI 7", "Rolade Ayam")
      const rawWords = exactCleanName.split(/\s+/);
      const cutIndex = rawWords.findIndex(w => ['pcs', '@', 'pack', '500g', '1000g', '250g', '500', '1000', '250'].includes(w.toLowerCase()));
      const coreTokens = (cutIndex > 0) ? rawWords.slice(0, cutIndex) : rawWords.slice(0, 3);
      const coreQuery = coreTokens.join(' ');

      const targetLower = exactOdooName.toLowerCase().trim();
      const registeredLower = registeredOdooName.toLowerCase().trim();
      const fallbackLower = fallbackName.toLowerCase().trim();
      const isExplicitJadi = targetLower.includes('[produk jadi]');
      // In PT PO, PT SO, and CV SO: ALWAYS prioritize [PRODUK LK] and strictly forbid [PRODUK JADI]
      const preferLk = !isExplicitJadi;

      // Distinguishing keywords that MUST be in the product
      const noiseWords = ['pcs', 'pack', 'g', 'gram', 'kg', 'dan', 'yang', 'atau', '@', 'mbg', 'coklat'];
      const keyTokens = exactOdooName
        .replace(/^\[.*?\]\s*/, '')
        .toLowerCase()
        .split(/[\s@()\-]+/)
        .filter(t => t.length > 0 && !noiseWords.includes(t));

      const cleanTarget = targetLower.replace(/[\(\)@\-\[\]]/g, ' ').replace(/\s+/g, ' ').trim();
      const cleanRegistered = registeredLower ? registeredLower.replace(/[\(\)@\-\[\]]/g, ' ').replace(/\s+/g, ' ').trim() : '';
      const targetCore = targetLower.replace(/^\[.*?\]\s*/, '').replace(/\s+/g, ' ').trim();
      const registeredCore = registeredLower ? registeredLower.replace(/^\[.*?\]\s*/, '').replace(/\s+/g, ' ').trim() : '';

      // Helper function to score dropdown candidates with strict product identity constraints
      function scoreCandidate(optText) {
        if (!optText) return -1;
        let score = 0;
        const txt = optText.toLowerCase().trim();

        // 1. NEVER pick create or search more options
        if (txt.startsWith('create ') || txt.startsWith('buat ') || txt.includes('search more') || txt.includes('cari lebih banyak')) {
          return -1;
        }

        // 2. STRICT RULE: In PT PO and CV SO, STRICTLY FORBID [PRODUK JADI] and REQUIRE [PRODUK LK]
        if (preferLk) {
          if (txt.includes('[produk jadi]')) return -1;
          if (!txt.includes('[produk lk]')) return -1;
        }

        // 3. HIGHEST PRIORITY: Exact match with registered name from Master Barang
        if (registeredLower && txt === registeredLower) {
          return 10000;
        }
        if (targetLower && txt === targetLower) {
          return 9000;
        }

        // 4. Normalized exact match (ignoring brackets, punctuation, and extra whitespace)
        const cleanOpt = txt.replace(/[\(\)@\-\[\]]/g, ' ').replace(/\s+/g, ' ').trim();
        if (cleanRegistered && cleanOpt === cleanRegistered) {
          return 8000;
        }
        if (cleanTarget && cleanOpt === cleanTarget) {
          return 7500;
        }

        // 5. Compare core name (without bracket prefix)
        const optCore = txt.replace(/^\[.*?\]\s*/, '').replace(/\s+/g, ' ').trim();
        if (registeredCore && optCore === registeredCore) {
          return 7000;
        }
        if (targetCore && optCore === targetCore) {
          return 6500;
        }

        // 6. Substring match of clean core
        if (registeredCore && optCore.includes(registeredCore)) {
          return 6000;
        }
        if (targetCore && optCore.includes(targetCore)) {
          return 5500;
        }

        // 7. PRODUCT IDENTITY & ATTRIBUTE CONSTRAINTS:
        // A. Primary Product Category Constraint
        const primaryCategories = [
          { key: 'rolade', aliases: ['rolade', 'rollade'] },
          { key: 'brs', aliases: ['brs'] },
          { key: 'bakso', aliases: ['bakso', 'baso'] },
          { key: 'sosis', aliases: ['sosis'] },
          { key: 'kornet', aliases: ['kornet', 'corned'] },
          { key: 'nugget', aliases: ['nugget'] },
          { key: 'jari', aliases: ['jari'] },
          { key: 'miniku', aliases: ['miniku'] },
        ];

        for (const cat of primaryCategories) {
          const targetHasCat = cat.aliases.some(a => targetLower.includes(a) || fallbackLower.includes(a));
          const optHasCat = cat.aliases.some(a => txt.includes(a));
          if (targetHasCat && !optHasCat) return -1; // Target is Rolade, candidate is not!
          if (!targetHasCat && optHasCat) return -1; // Target is NOT Jari-Jari, candidate is Jari-Jari!
        }

        // B. Meat Type & Flavor Variant Constraint (Ayam vs Sapi vs Ori/Coklat vs Merah)
        const targetHasSapi = targetLower.includes('sapi') || fallbackLower.includes('sapi');
        const targetHasAyam = targetLower.includes('ayam') || fallbackLower.includes('ayam');
        const targetHasOriOrCoklat = targetLower.includes('ori') || targetLower.includes('coklat') || fallbackLower.includes('ori') || fallbackLower.includes('coklat');
        const targetHasMerah = targetLower.includes('merah') || fallbackLower.includes('merah');

        const optHasSapi = txt.includes('sapi');
        const optHasAyam = txt.includes('ayam');
        const optHasOri = txt.includes('ori');
        const optHasMerah = txt.includes('merah');

        // If target specifies Sapi, candidate MUST have Sapi and CANNOT have Ayam
        if (targetHasSapi && (!optHasSapi || optHasAyam)) return -1;

        // If target specifies Ayam, candidate MUST have Ayam and CANNOT have Sapi
        if (targetHasAyam && (!optHasAyam || optHasSapi)) return -1;

        // CRITICAL: If target does NOT specify Ayam, candidate MUST NOT have Ayam!
        // This strictly prevents BRS Coklat / BRS Ori from ever selecting BRS Ayam!
        if (!targetHasAyam && optHasAyam) return -1;

        // CRITICAL: Merah constraint!
        // If target specifies Merah, candidate MUST have Merah and CANNOT have Ayam/Sapi
        if (targetHasMerah && (!optHasMerah || optHasAyam || optHasSapi)) return -1;
        // If target does NOT specify Merah, candidate MUST NOT have Merah!
        // This strictly prevents BRS Coklat / BRS Ori from ever selecting BRS Merah!
        if (!targetHasMerah && optHasMerah) return -1;
        if (targetHasMerah && optHasMerah) score += 3000;

        // If target specifies Ori or Coklat, strictly forbid Ayam/Merah and give Ori a massive bonus
        if (targetHasOriOrCoklat) {
          if (optHasAyam || optHasMerah) return -1;
          if (optHasOri) score += 3000;
        }

        // C. Variant Number Constraint (7 vs 13 vs 24 vs 30 vs 6)
        const variantNumbers = ['7', '13', '24', '30', '6'];
        for (const num of variantNumbers) {
          const numRegex = new RegExp(`(?:^|\\D)${num}(?:s|pcs|pack)?(?:\\D|$)`, 'i');
          const targetHasNum = numRegex.test(targetLower) || numRegex.test(fallbackLower);
          const optHasNum = numRegex.test(txt);
          if (targetHasNum && !optHasNum) return -1;
          if (!targetHasNum && optHasNum) {
            if (variantNumbers.some(n => {
              const r = new RegExp(`(?:^|\\D)${n}(?:s|pcs|pack)?(?:\\D|$)`, 'i');
              return r.test(targetLower) || r.test(fallbackLower);
            })) {
              return -1;
            }
          }
        }

        // D. Weight / Gram Variant Constraint (250 vs 500 vs 1000)
        // E.g. Rolade Ayam 250 g vs Rolade Ayam 1000 g
        const weightVariants = ['250', '500', '1000'];
        for (const w of weightVariants) {
          const wRegex = new RegExp(`(?:^|\\D)${w}\\s*(?:g|gram|kg)?(?:\\D|$)`, 'i');
          const targetHasWeight = wRegex.test(targetLower) || wRegex.test(fallbackLower);
          const optHasWeight = wRegex.test(txt);
          if (targetHasWeight && !optHasWeight) return -1;
          if (!targetHasWeight && optHasWeight) {
            if (weightVariants.some(otherW => {
              if (otherW === w) return false;
              const r = new RegExp(`(?:^|\\D)${otherW}\\s*(?:g|gram|kg)?(?:\\D|$)`, 'i');
              return r.test(targetLower) || r.test(fallbackLower);
            })) {
              return -1;
            }
          }
        }

        // D. Calculate Score based on matching distinctive tokens
        let matchedTokens = 0;

        for (const tok of keyTokens) {
          if (['lk', 'produk', 'pcs', 'g', 'gram', '500', '250', '1000'].includes(tok)) continue;
          if (txt.includes(tok)) {
            score += 25;
            matchedTokens++;
          } else if (tok.endsWith('s') && txt.includes(tok.slice(0, -1))) {
            score += 20;
            matchedTokens++;
          }
        }

        // CRITICAL: Must have at least 1 matched distinctive product token!
        if (matchedTokens === 0) {
          return -1;
        }

        // Extra bonus for [PRODUK LK] if preferLk
        if (preferLk && txt.includes('[produk lk]')) {
          score += 500;
        }

        return score;
      }

      // SMART RESUME GUARD:
      // If row i is ALREADY filled in Odoo, check if it matches the target product using scoreCandidate!
      const currentTableRows = getOrderLineRows();
      if (currentTableRows.length > i) {
        const checkRow = currentTableRows[i];
        const checkProdText = (checkRow.querySelector('td[name="product_id"], td[data-name="product_id"]')?.innerText || '').trim();
        const checkQtyText = (checkRow.querySelector('td[name="product_qty"], td[data-name="product_qty"], td[name="product_uom_qty"]')?.innerText || '').replace(/[.,]/g, '');
        const checkQtyNum = parseFloat(checkQtyText) || 0;
        
        if (checkProdText.length > 3 && !checkProdText.toLowerCase().includes('add a product') && checkQtyNum > 0) {
          const existingScore = scoreCandidate(checkProdText);
          if (existingScore > 0) {
            logMessage(`✓ Baris ${i + 1}/${items.length} sudah sesuai ("${checkProdText}"). Melanjutkan...`);
            successfulRows++;
            continue;
          } else {
            logMessage(`⚠️ Baris ${i + 1} saat ini "${checkProdText}" (tidak cocok). Mengganti ke produk yang sesuai...`);
          }
        }
      }

      logMessage(`📦 Baris ${i + 1}/${items.length}: Membuka baris untuk "${exactOdooName}"...`);

      // 1. ADD / VERIFY ROW
      const activeRow = await addNewRowWithVerification(i, timing);
      if (!activeRow) {
        logMessage(`❌ Gagal membuka baris ke-${i + 1}. Menghentikan proses.`);
        return successfulRows;
      }

      // 2. FILL PRODUCT
      let prodCell = activeRow.querySelector('td[name="product_id"], td[data-name="product_id"]')
        || findCellByColumnHeader(activeRow, ['product', 'produk', 'barang']);
      
      if (prodCell) {
        prodCell.click();
        await sleep(250);
      }

      let prodInput = activeRow.querySelector('td[name="product_id"] input, td[data-name="product_id"] input') 
        || activeRow.querySelector('input') 
        || document.activeElement;

      // Prepare multi-tier search queries prioritizing the exact name registered in Master Barang
      const searchQueries = [];
      function addQuery(q) {
        if (!q) return;
        const trimmed = q.replace(/\s+/g, ' ').trim();
        if (trimmed.length > 0 && !searchQueries.includes(trimmed)) {
          searchQueries.push(trimmed);
        }
      }

      // 1. If registered name from Master Barang is present
      if (registeredOdooName) {
        addQuery(registeredOdooName);
        const cleanReg = registeredOdooName.replace(/^\[.*?\]\s*/, '').trim();
        addQuery(cleanReg);
        const regWords = cleanReg.split(/\s+/);
        const cut = regWords.findIndex(w => ['pcs', '@', 'pack', '500g', '250g', '1000g', '500', '250', '1000'].includes(w.toLowerCase()));
        const coreReg = (cut > 0) ? regWords.slice(0, cut).join(' ') : regWords.slice(0, 3).join(' ');
        if (coreReg) {
          addQuery(coreReg);
          if (preferLk) addQuery(`[PRODUK LK] ${coreReg}`);
        }
      }

      // 2. Known product categories & variant numbers
      if (fallbackLower.includes('brs') || targetLower.includes('brs')) {
        if (targetLower.includes('7') || fallbackLower.includes('7')) {
          addQuery('[PRODUK LK] BRS ORI 7 PCS 500 g LK');
          addQuery('BRS ORI 7 PCS 500 g LK');
          addQuery('BRS ORI 7');
          if (preferLk) addQuery('[PRODUK LK] BRS ORI 7');
          addQuery('BRS 7');
          if (preferLk) addQuery('[PRODUK LK] BRS 7');
        } else if (targetLower.includes('13') || fallbackLower.includes('13')) {
          addQuery('BRS 13');
          if (preferLk) addQuery('[PRODUK LK] BRS 13');
        } else if (targetLower.includes('24') || fallbackLower.includes('24')) {
          const isMerah = targetLower.includes('merah') || fallbackLower.includes('merah');
          if (isMerah) {
            addQuery('[PRODUK LK] BRS Merah 24 PCS @ 500 g LK');
            addQuery('[PRODUK LK] BRS Merah 24');
            addQuery('BRS Merah 24');
            addQuery('BRS Merah');
          } else {
            addQuery('[PRODUK LK] BRS 24 PCS @ 500 g LK');
            addQuery('[PRODUK LK] BRS 24');
            addQuery('BRS 24');
          }
        } else if (targetLower.includes('30') || fallbackLower.includes('30')) {
          addQuery('BRS 30');
          if (preferLk) addQuery('[PRODUK LK] BRS 30');
        } else if (targetLower.includes('6') || fallbackLower.includes('6')) {
          addQuery('BRS 6');
          if (preferLk) addQuery('[PRODUK LK] BRS 6');
        }
      }

      if (fallbackLower.includes('rolade') || fallbackLower.includes('rollade') || targetLower.includes('rolade') || targetLower.includes('rollade')) {
        const isAyam = targetLower.includes('ayam') || fallbackLower.includes('ayam');
        const isSapi = targetLower.includes('sapi') || fallbackLower.includes('sapi');
        const meat = isAyam ? 'Ayam' : (isSapi ? 'Sapi' : '');
        const has250 = targetLower.includes('250') || fallbackLower.includes('250');
        const has1000 = targetLower.includes('1000') || fallbackLower.includes('1000');
        const weight = has250 ? '250' : (has1000 ? '1000' : '');

        if (meat) {
          if (weight) {
            addQuery(`[PRODUK LK] Rolade ${meat} ${weight} g LK`);
            addQuery(`[PRODUK LK] Rolade ${meat} ${weight}`);
            addQuery(`Rolade ${meat} ${weight}`);
          }
          addQuery(`[PRODUK LK] Rolade ${meat}`);
          addQuery(`Rolade ${meat}`);
        }
      }

      // 3. Fallback generic queries
      const normalizedExact = exactCleanName.replace(/rollade/gi, 'Rolade').replace(/\(.*?\)/g, '').trim();
      addQuery(normalizedExact);
      const normalizedCore = coreQuery.replace(/rollade/gi, 'Rolade').replace(/\(.*?\)/g, '').trim();
      if (normalizedCore) {
        addQuery(normalizedCore);
        if (preferLk) addQuery(`[PRODUK LK] ${normalizedCore}`);
      }

      let matchedItem = null;

      if (prodInput && prodInput.tagName === 'INPUT') {
        for (const query of searchQueries) {
          if (matchedItem) break;
          logMessage(`🔍 Mencari produk: "${query}"...`);

          prodInput.focus();
          prodInput.select();
          document.execCommand('selectAll', false, null);
          document.execCommand('delete', false, null);
          document.execCommand('insertText', false, query);
          prodInput.value = query;
          prodInput.dispatchEvent(new Event('input', { bubbles: true }));
          prodInput.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true }));
          prodInput.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true }));

          // Explicitly trigger jQuery UI autocomplete search if available
          try {
            if (window.jQuery) {
              window.jQuery(prodInput).autocomplete('search', query);
            }
          } catch (_) {}

          // Poll up to 14 times (3.5s) per query
          for (let attempt = 0; attempt < 14; attempt++) {
            await sleep(250);
            dismissDiscardModal();

            const dropdownOptions = Array.from(document.querySelectorAll('.ui-autocomplete .ui-menu-item:not(.o_m2o_dropdown_option), .o-autocomplete--dropdown-menu .dropdown-item, ul.ui-autocomplete li.ui-menu-item'))
              .filter(opt => {
                const rect = opt.getBoundingClientRect();
                return rect.width > 0 && rect.height > 0 && opt.style.display !== 'none';
              });

            if (dropdownOptions.length > 0) {
              const scored = dropdownOptions.map(opt => ({
                opt,
                text: opt.innerText.trim(),
                score: scoreCandidate(opt.innerText)
              })).filter(x => x.score > 0);

              scored.sort((a, b) => b.score - a.score);
              if (scored.length > 0) {
                // If input is still actively loading autocomplete from server, give it a brief moment
                if (prodInput.classList.contains('ui-autocomplete-loading') && attempt < 3) {
                  await sleep(250);
                  continue;
                }
                matchedItem = scored[0].opt;
                logMessage(`🎯 Menemukan kecocokan: "${scored[0].text}" (Skor: ${scored[0].score})`);
                break;
              }
            }
          }
        }

        if (matchedItem) {
          logMessage(`✓ Memilih: ${matchedItem.innerText.trim().substring(0, 35)}...`);
          const link = matchedItem.querySelector('a') || matchedItem;
          link.dispatchEvent(new MouseEvent('mouseenter', { bubbles: true, view: window }));
          link.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true, view: window }));
          link.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, cancelable: true, view: window }));
          link.click();
          matchedItem.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true, view: window }));
          matchedItem.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, cancelable: true, view: window }));
          matchedItem.click();

          try {
            if (window.jQuery && window.jQuery(matchedItem).data('ui-autocomplete-item')) {
              const itemData = window.jQuery(matchedItem).data('ui-autocomplete-item');
              window.jQuery(prodInput).trigger(window.jQuery.Event('autocompleteselect', { item: itemData }));
            }
          } catch (_) {}
          
          // VERIFY Odoo onchange RPC finishes and updates description/price/uom
          logMessage(`⏳ Menunggu Odoo memuat data produk #${i + 1}...`);
          await waitForProductOnchange(i, keyTokens, timing);
          dismissDiscardModal();
        } else {
          logMessage(`⚠️ Opsi [PRODUK LK] "${exactOdooName}" tidak muncul di dropdown.`);
          // CRITICAL: Clean up the empty invalid row so Odoo does NOT block subsequent rows!
          const trashBtn = activeRow.querySelector('.o_list_record_delete, .fa-trash-o, .fa-trash, button[name="delete"]');
          if (trashBtn) {
            trashBtn.click();
            await sleep(300);
            await waitForOdooRpcSettled(300);
          } else {
            prodInput.focus();
            document.execCommand('selectAll', false, null);
            document.execCommand('delete', false, null);
            prodInput.value = '';
            prodInput.dispatchEvent(new Event('input', { bubbles: true }));
          }
          continue;
        }
      } else {
        logMessage(`⚠️ Input produk baris ke-${i + 1} tidak ditemukan.`);
        continue;
      }

      // 3. SET QUANTITY & VERIFY
      logMessage(`✏️ Mengisi Qty: ${qty} Units...`);
      await setAndVerifyCell(
        i,
        'td[name="product_qty"], td[data-name="product_qty"], td[name="product_uom_qty"], td[data-name="product_uom_qty"]',
        ['quantity', 'qty', 'kuantitas', 'jumlah'],
        qty,
        'Quantity',
        timing
      );

      // 4. SET UNIT PRICE & VERIFY
      logMessage(`✏️ Mengisi Harga: Rp ${Math.round(price).toLocaleString('id-ID')}...`);
      await setAndVerifyCell(
        i,
        'td[name="price_unit"], td[data-name="price_unit"]',
        ['unit price', 'harga', 'price'],
        Math.round(price),
        'Unit Price',
        timing
      );

      // 5. DISCOUNT (%): In PT SO, follow invoice discount; in PT PO & CV SO, no discount
      if (mode === 'PT_SO') {
        const discVal = Number(item.discountPercent !== undefined && item.discountPercent !== null ? item.discountPercent : (item.discount || 0));
        if (discVal > 0) {
          logMessage(`✏️ Mengisi Diskon: ${discVal}%...`);
          await setAndVerifyCell(
            i,
            'td[name="discount"], td[data-name="discount"]',
            ['disc', 'discount', 'diskon'],
            discVal,
            'Discount (%)',
            timing
          );
          await waitForOdooRpcSettled(300);
        } else {
          logMessage(`✓ Diskon baris ${i + 1}: 0%`);
        }
      }

      // 6. TAXES: In PT PO & PT SO always 11%; in CV SO Taxes must be EMPTY (no PPN / tax)!
      if (isPtPo || mode === 'PT_SO') {
        logMessage(`✏️ Memastikan Taxes: 11%...`);
        await setTaxesField(i, timing, '11%');
        await waitForOdooRpcSettled(400);
      } else {
        logMessage(`🧹 Memastikan Taxes baris ${i + 1} kosong (CV SO tanpa Taxes)...`);
        await clearTaxesField(i, timing);
        await waitForOdooRpcSettled(400);
      }

      // 6. COMMIT & SETTLE ROW
      if (document.activeElement && typeof document.activeElement.blur === 'function') {
        document.activeElement.blur();
      }
      await waitForOdooRpcSettled(timing.delayAfterRowCommit);
      dismissOdooModals();

      successfulRows++;
      logMessage(`✅ Baris ${i + 1}/${items.length} selesai diverifikasi.`);
    }
    return successfulRows;
  }

  // Initialize
  setTimeout(() => {
    createFloatingWidget();
    loadStoredPayload();
  }, 1000);

  // Auto-sync clipboard when switching between windows / Chrome profiles
  window.addEventListener('focus', () => {
    pasteFromClipboard(false);
  });
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') {
      pasteFromClipboard(false);
    }
  });

  // Listen for direct Ctrl+V paste on the page
  document.addEventListener('paste', (e) => {
    const text = (e.clipboardData || window.clipboardData)?.getData('text');
    if (text && text.includes('LUCIFAX_ODOO_PAYLOAD:')) {
      e.preventDefault();
      applyPayloadText(text, true);
    }
  });

})();

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
          <strong style="color: #38BDF8; font-size: 13px;">Lucifax Odoo Assistant v1.1.2</strong>
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
      if (modal.offsetParent === null) continue;
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
      if (el.offsetParent !== null && !el.classList.contains('d-none') && el.style.display !== 'none') {
        return true;
      }
    }
    // 2. Check if "still loading" text exists in any visible element
    const centerSpinners = Array.from(document.querySelectorAll('div, span, p')).filter(el => 
      el.offsetParent !== null && el.children.length === 0 && (
        el.innerText.toLowerCase().includes('still loading') ||
        el.innerText.toLowerCase().includes('loading...')
      )
    );
    if (centerSpinners.length > 0) return true;

    // 3. jQuery active network calls
    if (window.jQuery && typeof window.jQuery.active === 'number' && window.jQuery.active > 0) {
      return true;
    }

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

  // Helper to set Odoo Many2One / Many2Many autocomplete dropdown with robust polling & selection
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
    input.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowDown', keyCode: 40, bubbles: true }));
    input.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true }));

    // Trigger jQuery UI autocomplete search directly if available
    if (window.jQuery) {
      try {
        window.jQuery(input).autocomplete('search', searchText);
      } catch (_) {}
    }

    // Poll up to 16 times (4 seconds) for autocomplete dropdown menu to appear
    let matchedItem = null;
    const searchTarget = (targetMatchText || searchText).toLowerCase().trim();
    const searchNormalized = searchTarget.replace(/\s+/g, ' ');

    for (let attempt = 0; attempt < 16; attempt++) {
      await sleep(250);
      dismissOdooModals();

      // Query ONLY visible dropdown menus currently rendered on screen
      const visibleMenus = Array.from(document.querySelectorAll('ul.ui-autocomplete, .o-autocomplete--dropdown-menu'))
        .filter(m => m.offsetParent !== null && m.style.display !== 'none');
      
      let options = [];
      if (visibleMenus.length > 0) {
        options = visibleMenus.flatMap(m => Array.from(m.querySelectorAll('.ui-menu-item:not(.o_m2o_dropdown_option), .dropdown-item')));
      }

      const cleanOptions = options.filter(opt => {
        if (opt.offsetParent === null) return false;
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

        // STRICT: NEVER fallback to cleanOptions[0] to prevent picking wrong tags like "Selesai"!
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
      
      // Wait for onchange partner / analytic account RPC to settle
      await waitForOdooRpcSettled(500);
      return true;
    } else {
      // CRITICAL: NEVER press Enter! Pressing Enter triggers Odoo's "Do you want to create...?" dialog!
      logMessage(`⚠️ Pilihan "${searchText}" tidak muncul di dropdown [${fieldName}]. Menutup dropdown agar tidak membuat record baru.`);
      input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', code: 'Escape', keyCode: 27, bubbles: true }));
      if (document.activeElement && typeof document.activeElement.blur === 'function') {
        document.activeElement.blur();
      }
      await sleep(200);
      dismissOdooModals();
    }
    return false;
  }

  // Helper to set Odoo Many2Many Tags (e.g. tag_ids: "Joko Setiawan")
  async function setTagsField(fieldName, tagText, labelKeywords = ['tags', 'tag']) {
    if (!tagText) return false;
    const container = document.querySelector(`div[name="${fieldName}"], [data-name="${fieldName}"], .o_field_many2manytags[name="${fieldName}"]`)
      || document.querySelector('.o_field_many2manytags');
    if (container) {
      // 1. Remove unwanted "Selesai" tag if it was accidentally attached
      const badges = Array.from(container.querySelectorAll('.badge, .o_tag, .badge-pill, .o_badge'));
      for (const b of badges) {
        if (b.innerText.toLowerCase().includes('selesai')) {
          const delBtn = b.querySelector('.o_delete, .fa-times, .close, a, i');
          if (delBtn) {
            delBtn.click();
            await sleep(250);
          }
        }
      }

      // 2. Check if target tag is already attached
      const updatedBadges = Array.from(container.querySelectorAll('.badge, .o_tag, .badge-pill, .o_badge'));
      if (updatedBadges.some(b => b.innerText.toLowerCase().includes(tagText.toLowerCase()))) {
        logMessage(`✓ Tag [${tagText}] sudah terpasang.`);
        return true;
      }
    }

    // Try full tag name first (e.g. "Joko Setiawan")
    let success = await setMany2OneField(fieldName, tagText, labelKeywords, false, tagText);
    
    // If not found, try searching with short prefix (e.g. "Joko") which reliably lists "Joko Setiawan"
    if (!success) {
      const shortPrefix = tagText.split(' ')[0]; // "Joko"
      if (shortPrefix && shortPrefix.toLowerCase() !== tagText.toLowerCase()) {
        logMessage(`...Mencoba mencari tag dengan kata kunci: "${shortPrefix}"...`);
        success = await setMany2OneField(fieldName, shortPrefix, labelKeywords, false, tagText);
      }
    }
    return success;
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

        logMessage('2. Mengatur Deliver To ke Jawa Tengah...');
        clickTab('Other Information');
        await sleep(200);
        await setMany2OneField('picking_type_id', 'Jawa Tengah: Receipts', ['deliver to', 'kirim ke']);

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

        logMessage('2. Mengisi Order Lines (Harga sebelum PPN)...');
        clickTab('Order Lines');
        await sleep(300);

        // Fill Items
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

  // Helper: Add new row and VERIFY it appears before proceeding
  async function addNewRowWithVerification(targetIndex, timing) {
    for (let attempt = 1; attempt <= timing.retries; attempt++) {
      dismissDiscardModal();
      // Wait for any pending Odoo loading / tax RPC to finish first!
      await waitForOdooRpcSettled(300);

      let currentRows = Array.from(document.querySelectorAll('table.o_section_and_note_list_view tbody tr.o_data_row, tbody tr.o_data_row'));
      if (currentRows.length > targetIndex) {
        return currentRows[targetIndex];
      }

      // Blur previous element so Odoo commits previous cell
      if (document.activeElement && typeof document.activeElement.blur === 'function') {
        document.activeElement.blur();
      }
      await sleep(250);

      const addBtns = Array.from(document.querySelectorAll('.o_field_x2many_list_row_add a, button.o_field_x2many_list_row_add, .o_field_widget a, a.o_field_x2many_list_row_add'));
      const addBtn = addBtns.find(b => b.innerText.toLowerCase().includes('add a product') || b.innerText.toLowerCase().includes('tambah produk'));
      if (!addBtn) {
        logMessage('⚠️ Tombol "Add a product" tidak ditemukan!');
        return null;
      }

      // Click cleanly without URL hash navigation
      addBtn.focus();
      addBtn.addEventListener('click', (e) => e.preventDefault(), { once: true });
      addBtn.click();

      // Poll up to 14 times (3.5s) for new row to appear
      for (let wait = 0; wait < 14; wait++) {
        await sleep(250);
        dismissDiscardModal();
        currentRows = Array.from(document.querySelectorAll('table.o_section_and_note_list_view tbody tr.o_data_row, tbody tr.o_data_row'));
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
      const rows = Array.from(document.querySelectorAll('table.o_section_and_note_list_view tbody tr.o_data_row, tbody tr.o_data_row'));
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
    const cleanTarget = formattedVal.replace(/[.,\s]/g, '');

    for (let attempt = 1; attempt <= timing.retries; attempt++) {
      dismissDiscardModal();

      // ALWAYS query fresh row from DOM to prevent detached node reference
      const rows = Array.from(document.querySelectorAll('table.o_section_and_note_list_view tbody tr.o_data_row, tbody tr.o_data_row'));
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
      const currentText = (cell.querySelector('input')?.value || cell.innerText || '').trim().replace(/[.,\s]/g, '');
      if (currentText === cleanTarget) {
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
      const freshRows = Array.from(document.querySelectorAll('table.o_section_and_note_list_view tbody tr.o_data_row, tbody tr.o_data_row'));
      const freshRow = freshRows[rowIndex];
      const freshCell = freshRow ? (freshRow.querySelector(cellSelector) || findCellByColumnHeader(freshRow, headerKeywords, fieldName)) : null;
      const verifiedVal = (freshCell?.querySelector('input')?.value || freshCell?.innerText || '').trim().replace(/[.,\s]/g, '');

      if (verifiedVal === cleanTarget || verifiedVal.includes(cleanTarget) || cleanTarget.includes(verifiedVal)) {
        logMessage(`✓ Kolom ${colName} [${formattedVal}] tersimpan`);
        return true;
      }

      logMessage(`⏳ Verifikasi ${colName} [${formattedVal}] belum terbaca (coba lagi ${attempt}/${timing.retries})...`);
      await sleep(350);
    }

    logMessage(`⚠️ Kolom ${colName} selesai diatur ke ${formattedVal}`);
    return false;
  }

  // Helper: Set Taxes field (in PT PO, Taxes always = 11%)
  async function setTaxesField(rowIndex, timing, taxTarget = '11%') {
    // 1. First check if cell already has 11% tag BEFORE doing any click
    const initialRows = Array.from(document.querySelectorAll('table.o_section_and_note_list_view tbody tr.o_data_row, tbody tr.o_data_row'));
    const initialRow = initialRows[rowIndex];
    if (initialRow) {
      const initialCell = initialRow.querySelector('td[name="taxes_id"], td[data-name="taxes_id"]') 
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

      const rows = Array.from(document.querySelectorAll('table.o_section_and_note_list_view tbody tr.o_data_row, tbody tr.o_data_row'));
      const row = rows[rowIndex];
      if (!row) {
        await sleep(250);
        continue;
      }

      // Find Taxes cell
      let cell = row.querySelector('td[name="taxes_id"], td[data-name="taxes_id"]') 
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
        input.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true }));
        await sleep(350);

        // Check dropdown options
        const dropdownOptions = Array.from(document.querySelectorAll('.ui-autocomplete .ui-menu-item, .o-autocomplete--dropdown-menu .dropdown-item'));
        const taxOption = dropdownOptions.find(opt => opt.innerText.trim().includes(taxTarget));
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
          input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', keyCode: 13, bubbles: true }));
          await waitForOdooRpcSettled(timing.delayAfterProduct);
        }
      }

      // Verify cell content
      const freshRows = Array.from(document.querySelectorAll('table.o_section_and_note_list_view tbody tr.o_data_row, tbody tr.o_data_row'));
      const freshRow = freshRows[rowIndex];
      const freshCell = freshRow ? (freshRow.querySelector('td[name="taxes_id"], td[data-name="taxes_id"]') || findCellByColumnHeader(freshRow, ['taxes', 'pajak'], 'taxes_id')) : null;
      if (freshCell && (freshCell.innerText.includes(taxTarget) || Array.from(freshCell.querySelectorAll('.badge, .o_tag')).some(b => b.innerText.includes(taxTarget)))) {
        logMessage(`✓ Taxes terverifikasi: ${taxTarget}`);
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
      const exactOdooName = (item.odooProductName && item.odooProductName.trim().length > 0)
        ? item.odooProductName.trim()
        : item.productName.trim();

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
      // CRITICAL: KEEP '@', '()', '-' because Odoo product names in database literally contain '@' (e.g. "@ 500 g")!
      const exactCleanName = exactOdooName.replace(/^\[.*?\]\s*/, '').replace(/\s+/g, ' ').trim();

      // Extract core query tokens for intelligent fallback (e.g. "BRS Merah 24", "BRS 13", "BRS ORI 7", "Rolade Ayam")
      const rawWords = exactCleanName.split(/\s+/);
      const cutIndex = rawWords.findIndex(w => ['pcs', '@', 'pack', '500g', '1000g', '500', '1000'].includes(w.toLowerCase()));
      const coreTokens = (cutIndex > 0) ? rawWords.slice(0, cutIndex) : rawWords.slice(0, 3);
      const coreQuery = coreTokens.join(' ');

      logMessage(`📦 Baris ${i + 1}/${items.length}: Membuka baris untuk "${exactOdooName}"...`);

      // 1. ADD / VERIFY ROW
      const activeRow = await addNewRowWithVerification(i, timing);
      if (!activeRow) {
        logMessage(`❌ Gagal membuka baris ke-${i + 1}. Menghentikan proses.`);
        return;
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

      const targetLower = exactOdooName.toLowerCase().trim();
      const isExplicitJadi = targetLower.includes('[produk jadi]');
      // In PT PO and CV SO, ALWAYS prioritize [PRODUK LK] and strictly forbid [PRODUK JADI]
      const preferLk = !isExplicitJadi && (isPtPo || isCvSo || targetLower.includes('[produk lk]'));

      // Distinguishing keywords that MUST be in the product
      const noiseWords = ['pcs', 'pack', 'g', 'gram', 'kg', 'dan', 'yang', 'atau', '@'];
      const keyTokens = exactOdooName
        .replace(/^\[.*?\]\s*/, '')
        .toLowerCase()
        .split(/[\s@()\-]+/)
        .filter(t => t.length > 0 && !noiseWords.includes(t));

      if (prodInput && prodInput.tagName === 'INPUT') {
        prodInput.focus();
        prodInput.select();
        document.execCommand('selectAll', false, null);
        document.execCommand('delete', false, null);
        // Type full clean name from Master Barang preserving '@' (e.g. "BRS Merah 24 PCS @ 500 g LK")
        document.execCommand('insertText', false, exactCleanName);
        prodInput.dispatchEvent(new Event('input', { bubbles: true }));
        prodInput.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true }));
        prodInput.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true }));

        // Wait up to 5 seconds for autocomplete dropdown items to appear
        let matchedItem = null;

        for (let attempt = 0; attempt < 20; attempt++) {
          await sleep(250);
          dismissDiscardModal();
          
          let dropdownOptions = Array.from(document.querySelectorAll('.ui-autocomplete .ui-menu-item:not(.o_m2o_dropdown_option), .o-autocomplete--dropdown-menu .dropdown-item'));
          
          // Fallback: If after 5 attempts (1.25s) no options appeared with exactCleanName, try core query (e.g. "BRS Merah 24")
          if (dropdownOptions.length === 0 && attempt === 5 && coreQuery && coreQuery !== exactCleanName) {
            logMessage(`...Mencoba kata kunci inti: "${coreQuery}"...`);
            prodInput.focus();
            document.execCommand('selectAll', false, null);
            document.execCommand('delete', false, null);
            document.execCommand('insertText', false, coreQuery);
            prodInput.dispatchEvent(new Event('input', { bubbles: true }));
            prodInput.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true }));
            prodInput.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true }));
            continue;
          }

          if (dropdownOptions.length > 0) {
            // STRICT RULE: If PT PO or preferLk, NEVER accept an option that contains [PRODUK JADI]!
            const validOptions = preferLk
              ? dropdownOptions.filter(opt => !opt.innerText.toLowerCase().includes('[produk jadi]'))
              : dropdownOptions;

            // Tier 1: Look for option containing [PRODUK LK] AND matching key tokens
            if (preferLk) {
              matchedItem = validOptions.find(opt => {
                const txt = opt.innerText.toLowerCase().trim();
                if (!txt.includes('[produk lk]')) return false;
                return keyTokens.every(tok => txt.includes(tok));
              });
            }

            // Tier 2: Exact string match with targetLower
            if (!matchedItem) {
              matchedItem = validOptions.find(opt => opt.innerText.toLowerCase().trim() === targetLower);
            }

            // Tier 3: Option containing [PRODUK LK] and matching main tokens
            if (!matchedItem && preferLk) {
              matchedItem = validOptions.find(opt => {
                const txt = opt.innerText.toLowerCase().trim();
                if (!txt.includes('[produk lk]')) return false;
                const mainTokens = keyTokens.filter(t => t !== 'lk');
                const matches = mainTokens.filter(tok => txt.includes(tok));
                return matches.length >= Math.max(1, mainTokens.length - 1);
              });
            }

            // Tier 4: General match for non-PT_PO
            if (!matchedItem && !preferLk) {
              matchedItem = validOptions.find(opt => {
                const txt = opt.innerText.toLowerCase().trim();
                return keyTokens.every(tok => txt.includes(tok));
              });
            }

            if (matchedItem) break;
          }
        }

        if (matchedItem) {
          logMessage(`✓ Memilih: ${matchedItem.innerText.trim().substring(0, 32)}...`);
          const link = matchedItem.querySelector('a') || matchedItem;
          link.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true, view: window }));
          link.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, cancelable: true, view: window }));
          link.click();
          
          // VERIFY Odoo onchange RPC finishes and updates description/price/uom
          logMessage(`⏳ Menunggu Odoo memuat data produk #${i + 1}...`);
          await waitForProductOnchange(i, keyTokens, timing);
          dismissDiscardModal();
        } else {
          // CRITICAL: Clear input if no [PRODUK LK] matched and SKIP row to prevent freezing subsequent rows!
          logMessage(`⚠️ Opsi [PRODUK LK] "${exactOdooName}" tidak muncul di dropdown. Melewati baris ini agar baris berikutnya tidak macet.`);
          prodInput.focus();
          document.execCommand('selectAll', false, null);
          document.execCommand('delete', false, null);
          prodInput.value = '';
          prodInput.dispatchEvent(new Event('input', { bubbles: true }));
          await sleep(300);
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

      // 5. SET TAXES (In PT PO: always 11%)
      if (isPtPo) {
        logMessage(`✏️ Mengisi Taxes: 11%...`);
        await setTaxesField(i, timing, '11%');
        await waitForOdooRpcSettled(500);
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

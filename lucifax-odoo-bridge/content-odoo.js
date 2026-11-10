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
          <strong style="color: #38BDF8; font-size: 13px;">Lucifax Odoo Assistant v1.0.5</strong>
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

  // Helper to find input by field name in Odoo DOM
  function findFieldInput(fieldName) {
    return document.querySelector(`div[name="${fieldName}"] input`)
      || document.querySelector(`input[name="${fieldName}"]`)
      || document.querySelector(`[data-name="${fieldName}"] input`);
  }

  // Helper to set Odoo Many2One autocomplete dropdown
  async function setMany2OneField(fieldName, searchText) {
    if (!searchText) return;
    const input = findFieldInput(fieldName);
    if (!input) {
      console.warn(`[Lucifax-Odoo] Field ${fieldName} tidak ditemukan`);
      return false;
    }

    input.focus();
    input.value = searchText;
    input.dispatchEvent(new Event('input', { bubbles: true }));
    input.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true }));

    await sleep(400);

    // Look for Odoo's autocomplete dropdown menu
    const dropdownItem = document.querySelector('.ui-autocomplete .ui-menu-item:not(.o_m2o_dropdown_option), .o-autocomplete--dropdown-menu .dropdown-item');
    if (dropdownItem) {
      dropdownItem.click();
    } else {
      input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', keyCode: 13, bubbles: true }));
      triggerEvents(input);
    }

    await sleep(250);
    return true;
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
    const tabs = Array.from(document.querySelectorAll('.nav-tabs a, .nav-link, [role="tab"]'));
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
        await setMany2OneField('partner_id', 'CV Fivafood and Meat Supply');
        setTextField('partner_ref', p.vendorRef || `${p.customerAlias || p.customerName} ${p.city}`);
        await setMany2OneField('currency_id', 'IDP');

        logMessage('2. Mengatur Deliver To ke Jawa Tengah...');
        clickTab('Other Information');
        await sleep(200);
        await setMany2OneField('picking_type_id', 'Jawa Tengah: Receipts');

        logMessage('3. Membuka tab Products...');
        clickTab('Products');
        await sleep(300);

        // Fill Items
        await fillOrderLines(p.items, 'PT_PO');

      } else if (mode === 'PT_SO') {
        // PT SO: Quotation (Sales PT)
        logMessage('1. Mengisi Customer PT SO...');
        await setMany2OneField('partner_id', p.ptSoCustomer || `${p.customerAlias} (${p.customerName})`);
        await setMany2OneField('pricelist_id', 'PFS Customer (IDP)');

        logMessage('2. Mengisi Order Lines (Harga sebelum PPN)...');
        clickTab('Order Lines');
        await sleep(300);

        // Fill Items
        await fillOrderLines(p.items, 'PT_SO');

      } else if (mode === 'CV_SO') {
        // CV SO: Quotation (Sales CV)
        logMessage('1. Mengisi Customer PT Fiva Jateng & Delivery Address...');
        await setMany2OneField('partner_id', 'PT Putra Fiva Sejahtera ( JAWA TENGAH )');
        await setMany2OneField('partner_shipping_id', p.cvSoDelivery || p.customerAlias || p.customerName);
        await setMany2OneField('pricelist_id', 'PFS Buy to CV 2023 (IDP)');

        logMessage('2. Mengisi Order Lines (Harga PO/SO)...');
        clickTab('Order Lines');
        await sleep(300);

        // Fill Items
        await fillOrderLines(p.items, 'CV_SO');
      }

      logMessage('🎉 SELESAI! Semua baris terisi (Draft). Silakan periksa angka lalu klik SAVE.', true);

    } catch (err) {
      console.error('[Lucifax-Odoo] Error during auto-fill:', err);
      logMessage(`Error: ${err.message}`, false, true);
    }
  }

  // Dismiss any "Record has been modified / discard changes" modal
  function dismissDiscardModal() {
    const modals = Array.from(document.querySelectorAll('.modal, .modal-dialog, [role="dialog"]'));
    for (const modal of modals) {
      if (modal.innerText.includes('discarded') || modal.innerText.includes('modified') || modal.innerText.includes('diabaikan')) {
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

  // Find cell by column header name in table
  function findCellByColumnHeader(row, headerKeywords) {
    const table = row.closest('table');
    if (!table) return null;
    const headers = Array.from(table.querySelectorAll('thead th'));
    const colIndex = headers.findIndex(th => {
      const text = th.innerText.toLowerCase();
      return headerKeywords.some(kw => text.includes(kw.toLowerCase()));
    });
    if (colIndex !== -1) {
      const cells = row.querySelectorAll('td');
      return cells[colIndex] || null;
    }
    return null;
  }

  // Helper to safely set cell value in Odoo editable tree
  async function setCellInput(row, cellSelector, headerKeywords, value) {
    if (value === undefined || value === null) return false;

    // 1. Find cell by selector
    let cell = row.querySelector(cellSelector);
    // 2. Fallback: find by column header name
    if (!cell && headerKeywords) {
      cell = findCellByColumnHeader(row, headerKeywords);
    }
    if (!cell) {
      console.warn('[Lucifax-Odoo] Cell tidak ditemukan untuk:', cellSelector);
      return false;
    }

    // Click cell to activate input
    cell.click();
    await sleep(300);

    let input = cell.querySelector('input');
    if (!input) {
      cell.dispatchEvent(new MouseEvent('dblclick', { bubbles: true }));
      await sleep(300);
      input = cell.querySelector('input');
    }

    // CRITICAL: ONLY operate if input is strictly inside this cell (never use external activeElement)
    if (input && (input.tagName === 'INPUT' || input.tagName === 'TEXTAREA')) {
      input.focus();
      input.select();
      const formattedVal = typeof value === 'number'
        ? (value % 1 === 0 ? Math.round(value).toString() : Number(value.toFixed(2)).toString())
        : value.toString();

      document.execCommand('selectAll', false, null);
      document.execCommand('insertText', false, formattedVal);
      input.value = formattedVal;
      input.dispatchEvent(new Event('input', { bubbles: true }));
      input.dispatchEvent(new Event('change', { bubbles: true }));
      input.dispatchEvent(new Event('blur', { bubbles: true }));
      await sleep(350);
      return true;
    }
    return false;
  }

  // Helper to extract clean query keywords for typing into Odoo's product search bar
  function getOdooSearchQuery(exactName) {
    if (!exactName) return '';
    // Strip [PRODUK LK], [PRODUK JADI] or any leading [bracket]
    const clean = exactName.replace(/^\[.*?\]\s*/, '').replace(/[@()\-]/g, ' ').replace(/\s+/g, ' ').trim();
    const words = clean.split(' ').filter(w => w.length > 0);
    const stopWords = ['pcs', 'pack', 'g', 'gram', 'kg', 'lk', 'produk', 'jadi'];
    
    const coreWords = [];
    for (const w of words) {
      if (stopWords.includes(w.toLowerCase()) && coreWords.length >= 2) {
        break;
      }
      coreWords.push(w);
      if (coreWords.length >= 3 && stopWords.includes(w.toLowerCase())) break;
    }
    return coreWords.length > 0 ? coreWords.join(' ') : clean;
  }

  // Fill product order lines in Odoo table using EXACT registered Odoo name
  async function fillOrderLines(items, mode) {
    for (let i = 0; i < items.length; i++) {
      dismissDiscardModal();

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

      // Query to type into Odoo search input (e.g. "BRS 13", "BRS ORI 7", "Rolade Ayam 1000")
      const searchStringToType = getOdooSearchQuery(exactOdooName);

      logMessage(`📦 Baris ${i + 1}/${items.length}: Mencari "${exactOdooName}" (ketik: "${searchStringToType}")...`);

      // 1. Commit/blur any previous cell first so Odoo doesn't think record is dirty
      if (document.activeElement && typeof document.activeElement.blur === 'function') {
        document.activeElement.blur();
      }
      await sleep(250);

      // 2. Find "Add a product" button
      const addBtns = Array.from(document.querySelectorAll('.o_field_x2many_list_row_add a, button.o_field_x2many_list_row_add, .o_field_widget a, a.o_field_x2many_list_row_add'));
      const addBtn = addBtns.find(b => b.innerText.toLowerCase().includes('add a product') || b.innerText.toLowerCase().includes('tambah produk'));

      if (addBtn) {
        // Prevent URL hash modification on anchor click
        addBtn.focus();
        addBtn.addEventListener('click', (e) => e.preventDefault(), { once: true });
        addBtn.click();
        
        // Wait 1200ms for Odoo to create and initialize the new line
        await sleep(1200);
        dismissDiscardModal();

        // 3. Identify the active row
        const allRows = document.querySelectorAll('tr.o_data_row');
        const activeRow = document.querySelector('tr.o_selected_row') || allRows[allRows.length - 1];

        if (activeRow) {
          let prodCell = activeRow.querySelector('td[name="product_id"], td[data-name="product_id"]')
            || findCellByColumnHeader(activeRow, ['product', 'produk', 'barang']);
          
          if (prodCell) {
            prodCell.click();
            await sleep(250);
          }

          let prodInput = activeRow.querySelector('td[name="product_id"] input, td[data-name="product_id"] input') 
            || activeRow.querySelector('input') 
            || document.activeElement;

          if (prodInput && prodInput.tagName === 'INPUT') {
            prodInput.focus();
            prodInput.select();
            document.execCommand('selectAll', false, null);
            document.execCommand('delete', false, null);
            // Type the clean search query into Odoo's input
            document.execCommand('insertText', false, searchStringToType);
            prodInput.dispatchEvent(new Event('input', { bubbles: true }));
            prodInput.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true }));
            prodInput.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true }));

            // Wait up to 4.5 seconds for autocomplete dropdown items to appear
            let matchedItem = null;
            const targetLower = exactOdooName.toLowerCase().trim();
            const isLk = targetLower.includes('[produk lk]');
            const isJadi = targetLower.includes('[produk jadi]');
            
            // Distinguishing keywords that MUST be in the product (excluding generic noise words)
            const noiseWords = ['pcs', 'pack', 'g', 'gram', 'kg', 'lk', 'produk', 'jadi', 'dan', 'yang', 'atau'];
            const keyTokens = exactOdooName
              .replace(/^\[.*?\]\s*/, '')
              .replace(/[@()\-]/g, ' ')
              .toLowerCase()
              .split(' ')
              .filter(t => t.length > 0 && !noiseWords.includes(t));

            for (let attempt = 0; attempt < 18; attempt++) {
              await sleep(250);
              dismissDiscardModal();
              const dropdownOptions = Array.from(document.querySelectorAll('.ui-autocomplete .ui-menu-item:not(.o_m2o_dropdown_option), .o-autocomplete--dropdown-menu .dropdown-item'));
              
              if (dropdownOptions.length > 0) {
                // Tier 1: Exact match with category tag
                matchedItem = dropdownOptions.find(opt => opt.innerText.toLowerCase().trim() === targetLower);

                // Tier 2: Category matching ([PRODUK LK]) AND all distinctive key tokens match
                if (!matchedItem) {
                  matchedItem = dropdownOptions.find(opt => {
                    const txt = opt.innerText.toLowerCase().trim();
                    if (isLk && !txt.includes('[produk lk]')) return false; // Strictly enforce [PRODUK LK]
                    if (isJadi && !txt.includes('[produk jadi]')) return false;
                    // ALL key tokens (e.g. ['brs', '13', '500'] or ['brs', 'ori', '7']) MUST be present!
                    return keyTokens.every(tok => txt.includes(tok));
                  });
                }

                // Tier 3: Category matching ([PRODUK LK]) AND at least key core tokens match
                if (!matchedItem && keyTokens.length > 1) {
                  matchedItem = dropdownOptions.find(opt => {
                    const txt = opt.innerText.toLowerCase().trim();
                    if (isLk && !txt.includes('[produk lk]')) return false;
                    if (isJadi && !txt.includes('[produk jadi]')) return false;
                    const matches = keyTokens.filter(tok => txt.includes(tok));
                    return matches.length >= Math.max(1, keyTokens.length - 1);
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
              
              // CRITICAL: Wait 1500ms for Odoo's onchange_product_id network RPC to finish
              await sleep(1500);
              dismissDiscardModal();
            } else {
              // NEVER press Enter blindly on unmatched dropdown to prevent discard modal!
              logMessage(`⚠️ Opsi "${exactOdooName}" tidak muncul di dropdown. Lewati pilihan barang ini.`);
              await sleep(500);
            }
          }

          // 4. Re-select the active row after Odoo's onchange re-render
          const updatedRow = document.querySelector('tr.o_selected_row') || activeRow;

          // 5. Set Quantity (QTY Packs, e.g. 75, 45, 45, 300 - NOT Karton!)
          logMessage(`✏️ Qty: ${qty} Pcs/Units...`);
          await setCellInput(
            updatedRow,
            'td[name="product_qty"], td[data-name="product_qty"], td[name="product_uom_qty"], td[data-name="product_uom_qty"]',
            ['quantity', 'qty', 'kuantitas', 'jumlah'],
            qty
          );
          // Wait 700ms for Odoo subtotal calculation
          await sleep(700);
          dismissDiscardModal();

          // 6. Set Unit Price
          logMessage(`✏️ Harga: Rp ${Math.round(price).toLocaleString('id-ID')}...`);
          await setCellInput(
            updatedRow,
            'td[name="price_unit"], td[data-name="price_unit"]',
            ['unit price', 'harga', 'price'],
            Math.round(price)
          );
          // Wait 700ms for Odoo price calculation
          await sleep(700);
          dismissDiscardModal();
        }
      }

      // Rest 1200ms before starting the next row so Odoo backend is completely settled
      logMessage(`✅ Baris ${i + 1} selesai.`);
      await sleep(1200);
    }
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

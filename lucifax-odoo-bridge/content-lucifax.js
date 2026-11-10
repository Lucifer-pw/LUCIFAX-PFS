// Content script running on Lucifax PFS Web App
console.log('[Lucifax-Odoo] Lucifax PFS Bridge Content Script Active');

// 1. Listen for copy events to automatically capture LUCIFAX_ODOO_PAYLOAD
document.addEventListener('copy', () => {
  navigator.clipboard.readText().then(text => {
    if (text && text.startsWith('LUCIFAX_ODOO_PAYLOAD:')) {
      try {
        const jsonStr = text.replace('LUCIFAX_ODOO_PAYLOAD:', '').trim();
        const payload = JSON.parse(jsonStr);
        chrome.runtime.sendMessage({
          action: 'STORE_INVOICE_PAYLOAD',
          payload: payload
        }, () => {
          console.log('[Lucifax-Odoo] Berhasil menangkap payload dari clipboard:', payload.invoiceNo);
        });
      } catch (e) {
        console.error('[Lucifax-Odoo] Gagal parse payload clipboard:', e);
      }
    }
  }).catch(() => {});
});

// 2. Also listen for window message if web app posts directly
window.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'LUCIFAX_ODOO_PAYLOAD' && event.data.payload) {
    chrome.runtime.sendMessage({
      action: 'STORE_INVOICE_PAYLOAD',
      payload: event.data.payload
    }, () => {
      console.log('[Lucifax-Odoo] Berhasil menerima payload dari window message:', event.data.payload.invoiceNo);
    });
  }
});

// Popup script for Lucifax Odoo Assistant

document.addEventListener('DOMContentLoaded', () => {
  const cardContent = document.getElementById('card-content');

  function render(payload) {
    if (payload && payload.invoiceNo) {
      cardContent.innerHTML = `
        <div class="inv-title">Invoice #${payload.invoiceNo}</div>
        <div class="inv-subtitle">
          <b>${payload.customerAlias || payload.customerName}</b> (${payload.city})
        </div>
        <div style="color: #4ADE80; font-size: 11px; margin-top: 6px; font-weight: 500;">
          Total: ${payload.items ? payload.items.length : 0} Item (${payload.grandTotalCarton || 0} Ktn)
        </div>
        <div style="color: #FBBF24; font-size: 11px; margin-top: 3px;">
          Rp ${Number(payload.grandTotal || 0).toLocaleString('id-ID')}
        </div>
        <div style="font-size: 10px; color: #94A3B8; margin-top: 8px; border-top: 1px solid #334155; padding-top: 6px;">
          PT SO: <i>${payload.ptSoCustomer}</i><br/>
          CV SO Delivery: <i>${payload.cvSoDelivery}</i><br/>
          Ref PO: <i>${payload.vendorRef}</i>
        </div>
      `;
    } else {
      cardContent.innerHTML = `
        <div style="color: #94A3B8; font-size: 11px; line-height: 1.4;">
          ⚠️ Belum ada transaksi dipilih.<br/><br/>
          Buka <b>Detail Invoice</b> di Lucifax PFS lalu klik tombol ungu <b>[ Siapkan ke Odoo ]</b>.
        </div>
      `;
    }
  }

  // Get current stored payload
  chrome.storage.local.get(['latestInvoicePayload'], (result) => {
    render(result.latestInvoicePayload);
  });
});

// Background Service Worker for Lucifax PFS - Odoo Bridge

chrome.runtime.onInstalled.addListener(() => {
  console.log('[Lucifax-Odoo] Extension Installed & Ready');
});

// Listen for messages from content scripts
chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (request.action === 'STORE_INVOICE_PAYLOAD') {
    chrome.storage.local.set({
      latestInvoicePayload: request.payload,
      lastUpdated: Date.now()
    }, () => {
      console.log('[Lucifax-Odoo] Invoice payload stored:', request.payload.invoiceNo);
      sendResponse({ status: 'OK' });
    });
    return true; // Keep message channel open for async response
  }

  if (request.action === 'GET_INVOICE_PAYLOAD') {
    chrome.storage.local.get(['latestInvoicePayload', 'lastUpdated'], (result) => {
      sendResponse({ payload: result.latestInvoicePayload || null, lastUpdated: result.lastUpdated || null });
    });
    return true;
  }
});

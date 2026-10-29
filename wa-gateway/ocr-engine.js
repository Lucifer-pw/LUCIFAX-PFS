const { createWorker } = require('tesseract.js');

let worker = null;
let isInitializing = false;
let initPromise = null;

async function getWorker() {
  if (worker) return worker;
  if (initPromise) return initPromise;

  initPromise = (async () => {
    try {
      console.log('[LOCAL OCR] 🔄 Menginisialisasi Tesseract OCR lokal (ind+eng)...');
      const w = await createWorker('ind+eng');
      worker = w;
      console.log('[LOCAL OCR] ✅ Tesseract OCR siap digunakan secara lokal.');
      return worker;
    } catch (err) {
      console.error('[LOCAL OCR ERROR] Gagal inisialisasi worker:', err.message);
      initPromise = null;
      throw err;
    }
  })();

  return initPromise;
}

/**
 * Perform local OCR on image buffer or path
 * @param {Buffer|string} imageSource - Buffer or local file path
 * @returns {Promise<{text: string, confidence: number}>}
 */
async function recognizeImage(imageSource) {
  try {
    const w = await getWorker();
    const result = await w.recognize(imageSource);
    return {
      text: result?.data?.text || '',
      confidence: result?.data?.confidence || 0
    };
  } catch (err) {
    console.error('[LOCAL OCR RECOGNIZE ERROR]:', err.message);
    return { text: '', confidence: 0, error: err.message };
  }
}

async function terminateWorker() {
  if (worker) {
    try {
      await worker.terminate();
    } catch (_) {}
    worker = null;
    initPromise = null;
  }
}

module.exports = {
  getWorker,
  recognizeImage,
  terminateWorker
};

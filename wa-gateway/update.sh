#!/bin/bash
# ============================================
# L-W.A.V.I.S Gateway Auto-Updater
# Lucifax-PFS WhatsApp Gateway
# ============================================

REPO_BASE="https://raw.githubusercontent.com/Lucifer-pw/LUCIFAX-PFS/main/wa-gateway"
GATEWAY_DIR="$HOME/wa-gateway"

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  🔄 L-W.A.V.I.S Gateway Updater                 ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

cd "$GATEWAY_DIR" || { echo "❌ Folder $GATEWAY_DIR tidak ditemukan!"; exit 1; }

# Tampilkan versi lokal saat ini
if [ -f version.json ]; then
  LOCAL_VER=$(grep -o '"gateway": "[^"]*"' version.json | head -1 | cut -d'"' -f4)
  echo "📌 Versi lokal saat ini: v$LOCAL_VER"
else
  echo "📌 Versi lokal: TIDAK DIKETAHUI (version.json tidak ada)"
fi

echo ""
echo "⬇️  Mengunduh file terbaru dari GitHub..."
echo ""

# Download semua file gateway
FILES="server.js autonomous-po-processor.js firebase-adapter.js ocr-engine.js bank-slip-parser.js version.json"

for f in $FILES; do
  echo -n "  📥 $f ... "
  if curl -sL -o "$f" "$REPO_BASE/$f"; then
    echo "✅"
  else
    echo "❌ GAGAL"
  fi
done

echo ""

# Tampilkan versi baru
if [ -f version.json ]; then
  NEW_VER=$(grep -o '"gateway": "[^"]*"' version.json | head -1 | cut -d'"' -f4)
  CHANGELOG=$(grep -o '"changelog": "[^"]*"' version.json | head -1 | cut -d'"' -f4)
  echo "✅ Update selesai! Versi baru: v$NEW_VER"
  echo "📝 Changelog: $CHANGELOG"
else
  echo "✅ Update selesai!"
fi

echo ""
echo "🔄 Restart gateway..."

# Restart: coba pm2 dulu, fallback manual
if command -v pm2 &> /dev/null; then
  pm2 restart wa-gateway 2>/dev/null || pm2 restart server 2>/dev/null || {
    echo "⚠️ pm2 restart gagal, restart manual..."
    pkill -f "node.*server.js" 2>/dev/null
    sleep 1
    nohup node server.js > gateway.log 2>&1 &
  }
else
  pkill -f "node.*server.js" 2>/dev/null
  sleep 1
  nohup node server.js > gateway.log 2>&1 &
fi

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  ✅ Gateway berhasil diupdate dan direstart!     ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

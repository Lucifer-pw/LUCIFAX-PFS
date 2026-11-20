#!/bin/bash
# ============================================
# L-W.A.V.I.S Gateway Auto-Updater
# Lucifax-PFS WhatsApp Gateway
# ============================================

REPO_BASE="https://raw.githubusercontent.com/Lucifer-pw/LUCIFAX-PFS/main/wa-gateway"
GATEWAY_DIR="$HOME/wa-gateway"

echo ""
echo "=============================================="
echo "  L-W.A.V.I.S Gateway Updater"
echo "=============================================="
echo ""

cd "$GATEWAY_DIR" || { echo "Folder $GATEWAY_DIR tidak ditemukan!"; exit 1; }

# Tampilkan versi lokal saat ini
if [ -f version.json ]; then
  LOCAL_VER=$(node -e "try{console.log(require('./version.json').gateway||'')}catch(_){}" 2>/dev/null)
  [ -z "$LOCAL_VER" ] && LOCAL_VER=$(grep -o '"gateway": "[^"]*"' version.json | head -1 | cut -d'"' -f4)
  echo "Versi lokal saat ini: v$LOCAL_VER"
else
  echo "Versi lokal: TIDAK DIKETAHUI (version.json tidak ada)"
fi

echo ""
echo "Mengunduh file terbaru dari GitHub..."
echo ""

# Download semua file gateway (kecuali update.sh disimpan terpisah agar tidak merusak eksekusi bash)
FILES="server.js autonomous-po-processor.js wavis-interactive-engine.js wavis-pdf-generator.js fiva-logo.bin firebase-adapter.js notification-dispatcher.js ocr-engine.js bank-slip-parser.js test-wavis-engine.js version.json update.bat"
CACHE_BUST="?t=$(date +%s)"

for f in $FILES; do
  printf "  %s ... " "$f"
  if curl -sL -o "$f" "$REPO_BASE/$f$CACHE_BUST"; then
    echo "OK"
  else
    echo "GAGAL"
  fi
done

# Download update.sh ke file sementara agar tidak terjadi 'syntax error near unexpected token else'
printf "  update.sh ... "
if curl -sL -o "update.sh.tmp" "$REPO_BASE/update.sh$CACHE_BUST"; then
  echo "OK"
else
  echo "GAGAL"
fi

echo ""

# Tampilkan versi baru & changelog
if [ -f version.json ]; then
  NEW_VER=$(node -e "try{console.log(require('./version.json').gateway||'')}catch(_){}" 2>/dev/null)
  [ -z "$NEW_VER" ] && NEW_VER=$(grep -o '"gateway": "[^"]*"' version.json | head -1 | cut -d'"' -f4)
  CHANGELOG=$(node -e "try{console.log(require('./version.json').changelog||'')}catch(_){}" 2>/dev/null)
  echo "Update selesai! Versi baru: v$NEW_VER"
  [ -n "$CHANGELOG" ] && echo "Changelog: $CHANGELOG"
else
  echo "Update selesai!"
fi

echo ""
echo "Restart gateway..."

# Restart: coba pm2 dulu, fallback manual
if command -v pm2 &> /dev/null; then
  pm2 restart wa-gateway 2>/dev/null || pm2 restart server 2>/dev/null || {
    echo "pm2 restart gagal, restart manual..."
    pkill -f "node.*server.js" 2>/dev/null
    sleep 2
    nohup node server.js > gateway.log 2>&1 &
  }
else
  pkill -f "node.*server.js" 2>/dev/null
  sleep 2
  nohup node server.js > gateway.log 2>&1 &
fi

echo ""
echo "=============================================="
echo "  Gateway berhasil diupdate dan direstart!"
echo "=============================================="
echo ""

# Ganti update.sh dengan file baru di baris paling akhir agar bash tidak terganggu pergeseran file descriptor
if [ -f "update.sh.tmp" ]; then
  mv -f "update.sh.tmp" "update.sh" 2>/dev/null
  chmod +x "update.sh" 2>/dev/null
fi
exit 0

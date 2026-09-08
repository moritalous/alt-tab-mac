#!/bin/bash
# ビルドして ~/Applications にインストールし、起動する
set -euo pipefail
cd "$(dirname "$0")"

./build.sh
DEST="$HOME/Applications/AltTabMac.app"
mkdir -p "$HOME/Applications"
pkill -x AltTabMac 2>/dev/null || true
rm -rf "$DEST"
cp -R build/AltTabMac.app "$DEST"
# ad-hoc 署名はビルドごとにハッシュが変わるため、古い許可エントリを消して再登録させる
tccutil reset Accessibility local.kazuaki.AltTabMac >/dev/null 2>&1 || true
open "$DEST"
echo "installed: $DEST"
echo "初回は システム設定 > プライバシーとセキュリティ > アクセシビリティ で AltTabMac を許可してください。"

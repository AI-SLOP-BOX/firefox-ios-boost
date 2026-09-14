#!/bin/bash
# uBOL相当リストの更新スクリプト (安全側変換)。
# 使い方: ./update_ubol_lists.sh [出力先]
# 既定出力: ../Sources/WebVideoBoost/AdBlock/Lists
set -euo pipefail
OUT="${1:-../Sources/WebVideoBoost/AdBlock/Lists}"
mkdir -p "$OUT"
python3 "$(dirname "$0")/ublock_to_webkit.py" --out "$OUT" --max-per-file 45000
echo "generated lists in $OUT"
ls -lh "$OUT"

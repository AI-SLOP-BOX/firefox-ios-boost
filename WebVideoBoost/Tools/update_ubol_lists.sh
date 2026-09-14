#!/bin/bash
# uBOL内包リストの再ビルド。既定はバージョン固定の内包raw (../FilterLists) から生成。
# 使い方:
#   ./update_ubol_lists.sh                    # 内包raw -> Sources/.../AdBlock/Lists
#   ./update_ubol_lists.sh [出力先]            # 出力先だけ変える
#   ./fetch_ubol_lists.sh && ./update_ubol_lists.sh   # 最新に更新してから再ビルド
set -euo pipefail
OUT="${1:-../Sources/WebVideoBoost/AdBlock/Lists}"
RAW_DIR="$(dirname "$0")/../FilterLists"
mkdir -p "$OUT"
python3 "$(dirname "$0")/ublock_to_webkit.py" --out "$OUT" --max-per-file 45000 --offline \
  "$RAW_DIR/easylist.txt" "$RAW_DIR/easyprivacy.txt" "$RAW_DIR/peter-lowe.txt" \
  "$RAW_DIR/uassets-filters.txt" "$RAW_DIR/uassets-badware.txt" "$RAW_DIR/uassets-privacy.txt" \
  "$RAW_DIR/uassets-unbreak.txt" "$RAW_DIR/uassets-quick-fixes.txt"
echo "generated lists in $OUT"
ls -lh "$OUT"

#!/bin/bash
# uBOL既定リストの取得 (バージョン固定用)。curl使用 (pythonのSSLが壊れた環境でも動く)。
# 使い方: ./fetch_ubol_lists.sh [出力先]
# 既定出力: ../FilterLists
# manifest.json に取得日時・URL・SHA256を記録する。
set -euo pipefail
OUT="${1:-../FilterLists}"
mkdir -p "$OUT"

fetch() {
  local url="$1" dest="$2"
  echo "fetch $url"
  curl -sSL --retry 3 --max-time 120 -o "$dest" "$url"
}

fetch "https://easylist.to/easylist/easylist.txt"                    "$OUT/easylist.txt"
fetch "https://easylist.to/easylist/easyprivacy.txt"                "$OUT/easyprivacy.txt"
fetch "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0&mimetype=plaintext" "$OUT/peter-lowe.txt"
fetch "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters.txt"     "$OUT/uassets-filters.txt"
fetch "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/badware.txt"     "$OUT/uassets-badware.txt"
fetch "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/privacy.txt"     "$OUT/uassets-privacy.txt"
fetch "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/unbreak.txt"    "$OUT/uassets-unbreak.txt"
fetch "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/quick-fixes.txt" "$OUT/uassets-quick-fixes.txt"

python3 - "$OUT" <<'EOF'
import hashlib, json, os, sys, datetime
out = sys.argv[1]
manifest = {"fetched_at": datetime.datetime.now(datetime.timezone.utc).isoformat(), "files": {}}
for fn in sorted(os.listdir(out)):
    if not fn.endswith(".txt"):
        continue
    p = os.path.join(out, fn)
    h = hashlib.sha256(open(p, "rb").read()).hexdigest()
    with open(p, encoding="utf-8", errors="replace") as f:
        lines = sum(1 for _ in f)
    manifest["files"][fn] = {"sha256": h, "lines": lines, "bytes": os.path.getsize(p)}
json.dump(manifest, open(os.path.join(out, "manifest.json"), "w"), indent=1)
print(json.dumps(manifest, indent=1)[:800])
EOF

ls -lh "$OUT"

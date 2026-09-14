#!/usr/bin/env python3
"""uBO/EasyList -> WebKit content-blocker JSON 変換ツール (省メモリ版)。

使い方:
    python3 ublock_to_webkit.py --out ./lists --max-per-file 45000
    python3 ublock_to_webkit.py --out ./lists --lite          # 軽量版 (~15k rules)
    python3 ublock_to_webkit.py --out ./lists --offline      # Tools/lists/*.txt を変換のみ

入力 (フル既定):
    - https://easylist.to/easylist/easylist.txt
    - https://easylist.to/easylist/easyprivacy.txt
    - https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0&mimetype=plaintext
    - https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters.txt
    - https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/badware.txt
    - https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/privacy.txt
    - https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/unbreak.txt (例外用)

入力 (--lite: 体感ブロック率を保ちつつルール数を約1/3に):
    - easylist.txt + Peter Lowe + uAssets filters.txt のみ
    (easyprivacy/badware/privacyは外す。メモリ最優先の端末向け)

出力:
    <out>/wvb-ubo-part-N.json   (WebKit content-blocker形式の配列)
    <out>/cosmetic_selectors.json (## フィルタから抽出したセレクタ配列。cosmetic.jsに埋め込む用)

省メモリ方針:
    - CSS要素非表示は JS MutationObserver ではなく WebKitネイティブの
      css-display-none ルールとしてJSONに直接埋め込む (--emit-css-rules, 既定ON, 上限あり)。
      ネイティブ側で処理されるためJSヒープ・CPUを使わない。
    - ネットワーク基本形のみ変換 (以下略):
        ||example.com^            -> block
        @@||example.com^          -> ignore-previous-rules
        ##.ad-banner              -> css-display-none (JSON内 + selectorsへ)
        ||ads.com^$third-party    -> load-type:third-party
        ||x.com^$script,image     -> resource-type
        ||x.com^$domain=a.com|b.c -> if-domain / unless-domain (肯定のみ対応)
"""
from __future__ import annotations
import argparse
import json
import os
import re
import sys
import urllib.request

DEFAULT_URLS = [
    "https://easylist.to/easylist/easylist.txt",
    "https://easylist.to/easylist/easyprivacy.txt",
    "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0&mimetype=plaintext",
    "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters.txt",
    "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/badware.txt",
    "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/privacy.txt",
    "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/unbreak.txt",
]

LITE_URLS = [
    "https://easylist.to/easylist/easylist.txt",
    "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0&mimetype=plaintext",
    "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters.txt",
    "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/unbreak.txt",
]

# css-display-none としてJSONに埋め込むセレクタ数上限。
# WebKitの50k/リスト制限を圧迫しないよう既定1500。残りはcosmetic.js側で処理。
DEFAULT_MAX_CSS_RULES = 1500

RESOURCE_MAP = {
    "script": "script",
    "image": "image",
    "stylesheet": "style-sheet",
    "style": "style-sheet",
    "css": "style-sheet",
    "media": "media",
    "font": "font",
    "xmlhttprequest": "fetch",
    "xhr": "fetch",
    "fetch": "fetch",
    "websocket": "fetch",
    "subdocument": "document",
    "document": "document",
    "other": "other",
    "object": None,  # WebKitにobject相当なし -> スキップ側で弾く
    "popup": None,
    "inline-script": None,
}

SKIP_OPTION_SUBSTRINGS = (
    "redirect=", "csp=", "removeparam=", "redirect-rule=",
    "denyallow=", "header=", "permissions=", "replace=",
    "empty", "mp4", "mediaredir",
)

PROCEDURAL_MARKERS = (":has(", ":has-text(", ":matches-css(", ":xpath(", ":upward(", ":remove(")


def fetch_all(urls: list[str], timeout: int = 30) -> list[str]:
    lines: list[str] = []
    for url in urls:
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "WebVideoBoost/1.0"})
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                text = resp.read().decode("utf-8", errors="replace")
            file_lines = text.splitlines()
            lines.extend(file_lines)
            print(f"fetched {url}: {len(file_lines)} lines", file=sys.stderr)
        except Exception as e:  # noqa: BLE001 - 1つ失敗しても続行
            print(f"WARN: fetch failed {url}: {e}", file=sys.stderr)
    return lines


def parse_hosts_line(line: str) -> str | None:
    # Peter Lowe hosts形式: "127.0.0.1 ads.example.com"
    parts = line.strip().split()
    if len(parts) == 2 and (parts[0].startswith("127.") or parts[0] == "0.0.0.0"):
        host = parts[1].strip()
        if host and host != "localhost":
            return f"||{host}^"
    return None


def escape_url_filter_literal(s: str) -> str:
    # WebKit url-filterは正規表現。uBOのプレーン文字列部分をエスケープする
    out = []
    for ch in s:
        if ch.isalnum() or ch in ("-", "_", ".", "/", ":", "?", "=", "&", "%", "#", "@"):
            # WebKitでは . はエスケープ推奨だが互換のためドットはエスケープする
            if ch == ".":
                out.append("\\.")
            else:
                out.append(ch)
        elif ch in ("*", "^", "|", "+", "(", ")", "[", "]", "{", "}", "$", "\\"):
            # ^ と | はuBOアンカーとして別処理するのでここには来ない想定。来たらエスケープ
            out.append("\\" + ch)
        else:
            out.append("\\" + ch)
    return "".join(out)


def convert_network_filter(line: str) -> dict | None:
    orig = line.strip()
    if not orig or orig.startswith(("!", "#", "@#", "[Adblock")):
        return None
    # コメント・要素系は別処理
    if "##" in orig or "#@#" in orig or "#?#" in orig:
        return None
    if orig.startswith("##+js") or "##^" in orig:
        return None
    for m in PROCEDURAL_MARKERS:
        if m in orig:
            return None

    is_exception = orig.startswith("@@")
    body = orig[2:] if is_exception else orig

    # オプション分割 ($ はURL中に現れうるが、uBOでは末尾$以降がオプション)
    options: list[str] = []
    if "$" in body:
        # 最後の$をオプション区切りとみなす (URLに$を含む例は稀)
        idx = body.rfind("$")
        options = [o.strip() for o in body[idx + 1:].split(",") if o.strip()]
        body = body[:idx]

    # スキップ判定
    opt_joined = ",".join(options)
    if any(s in opt_joined for s in SKIP_OPTION_SUBSTRINGS):
        return None
    if "denyallow=" in opt_joined:
        return None
    # domain/from に正規表現やワイルドカード混在はスキップ
    for o in options:
        if o.startswith(("domain=", "from=", "to=")) and ("/" in o or "*" in o):
            return None

    # --- URL パターン -> url-filter正規表現 ---
    url_filter: str | None = None
    b = body
    if b.startswith("||"):
        host_part = b[2:]
        # パス区切りまでをドメイン部とする
        m = re.split(r"[\/\^\*\?]", host_part, maxsplit=1)
        domain = m[0]
        rest = host_part[len(domain):]
        if not domain or "*" in domain or "/" in body[2:2+1:]:
            return None
        if "." not in domain and domain != "localhost":
            return None
        domain_re = escape_url_filter_literal(domain)
        # ^ はセパレータ (末尾/クエリ/終端)。WebKit正規表現で近似
        if rest.startswith("^"):
            url_filter = f"^https?://([^/]+\\.)?{domain_re}([/:?#]|$)"
        elif rest == "" or rest == "*":
            url_filter = f"^https?://([^/]+\\.)?{domain_re}"
        else:
            # パス付き: 前方一致として扱う
            path_re = escape_url_filter_literal(rest).replace("\\*", ".*")
            url_filter = f"^https?://([^/]+\\.)?{domain_re}{path_re}"
    elif b.startswith("|"):
        # |http://... 先頭アンカー
        lit = b.lstrip("|")
        lit_re = escape_url_filter_literal(lit).replace("\\*", ".*")
        url_filter = "^" + lit_re
    elif b.startswith("/") and b.endswith("/") and len(b) > 2:
        # 純正規表現はWebKitでも使えるが、暴発防止で長さ制限
        inner = b[1:-1]
        if len(inner) > 200 or "**" in inner:
            return None
        url_filter = inner
    else:
        # プレーン部分一致 (例: "ads.js", "/banner/")
        if len(b) < 4 or len(b) > 150:
            return None
        if any(m in b for m in PROCEDURAL_MARKERS):
            return None
        url_filter = escape_url_filter_literal(b).replace("\\*", ".*")

    trigger: dict = {"url-filter": url_filter}
    action: dict

    # --- オプション -> trigger ---
    load_types: list[str] = []
    resource_types: list[str] = []
    if_domains: list[str] = []
    unless_domains: list[str] = []

    for o in options:
        if o == "third-party" or o == "3p":
            trigger["load-type"] = ["third-party"]
        elif o == "first-party" or o == "1p":
            trigger["load-type"] = ["first-party"]
        elif o in RESOURCE_MAP:
            mapped = RESOURCE_MAP[o]
            if mapped is None:
                return None  # 表現できない種別を含む -> スキップ
            resource_types.append(mapped)
        elif o.startswith("~"):
            # 除外種別 (例: ~stylesheet) はWebKitにない -> 安全のためスキップ
            base = o[1:]
            if base in RESOURCE_MAP or base in ("third-party", "first-party", "3p", "1p"):
                return None
            # 不明な否定は無視して続行しない (厳しめ)
            return None
        elif o.startswith("domain="):
            domains = o[len("domain="):].split("|")
            for d in domains:
                if not d:
                    continue
                if d.startswith("~"):
                    unless_domains.append(d[1:])
                else:
                    if_domains.append(d)
        elif o in ("", "empty"):
            return None
        elif o in ("important", "badfilter", "match-case"):
            # importantはWebKitに優先度概念がないため無視 (blockとして扱う)
            # badfilterは打ち消しだが、順序依存のため今回はスキップ扱いにしない (後段で除外も検討)
            if o == "badfilter":
                return None
            continue
        elif o.startswith(("script=", "all", "popup", "inline")):
            return None
        else:
            # 未知オプションは安全側で無視ではなくスキップ
            # ただしよくある無害なものは許容
            if o not in ("generichide", "genericblock", "elemhide", "jsinject", "urlskip"):
                return None

    # third-partyとfirst-partyの両立不可
    if "load-type" in trigger and not isinstance(trigger["load-type"], list):
        pass
    if resource_types:
        # WebKitは resource-type 配列対応。document単独はmain-document扱いに注意
        trigger["resource-type"] = sorted(set(resource_types))
    if if_domains:
        # ワイルドカード/正規表現が混ざっていたら上で弾いている
        trigger["if-domain"] = if_domains
    if unless_domains:
        trigger["unless-domain"] = unless_domains

    # 例外ルールは ignore-previous-rules
    if is_exception:
        # WebKitのignoreは同じurl-filterにマッチした直前ルールを無効化する。
        # 変換後のfilterが広すぎると誤って無効化するため、||始まりのみ採用
        if not body.startswith("||"):
            return None
        action = {"type": "ignore-previous-rules"}
    else:
        action = {"type": "block"}

    return {"trigger": trigger, "action": action}


def convert_cosmetic(line: str) -> str | None:
    s = line.strip()
    if not s or s.startswith("!") or s.startswith("[Adblock"):
        return None
    if s.startswith("#@#"):
        return None
    if "##+js" in s or "##^" in s or "#?#" in s:
        return None
    for m in PROCEDURAL_MARKERS:
        if m in s:
            return None
    if "##" not in s:
        return None
    # domain##selector 形式。ドメイン指定付きは汎用リストでは扱わずスキップ (誤消し防止)
    # 例外: ドメインなし (##.ad) のみ採用
    parts = s.split("##", 1)
    if len(parts) != 2:
        return None
    domains, selector = parts
    selector = selector.strip()
    if domains.strip() not in ("", "*"):
        return None
    if not selector or len(selector) > 200:
        return None
    if selector.startswith("+js"):
        return None
    # 妥当そうなセレクタのみ
    if not re.match(r"^[.#\[a-zA-Z0-9_\-:=\"'\^\$\*\|\.\s,>~\+()]+$", selector):
        return None
    return selector


def convert_lines(lines: list[str]) -> tuple[list[dict], list[str]]:
    network_rules: list[dict] = []
    selectors: list[str] = []
    seen_rules: set[str] = set()
    for raw in lines:
        line = raw.strip()
        if not line:
            continue
        # hosts形式
        if re.match(r"^(127\.|0\.0\.0\.0)\s+\S+", line):
            conv = parse_hosts_line(line)
            if conv:
                r = convert_network_filter(conv)
                if r:
                    key = json.dumps(r, sort_keys=True)
                    if key not in seen_rules:
                        seen_rules.add(key)
                        network_rules.append(r)
            continue
        if line.startswith("!") or line.startswith("[Adblock"):
            continue
        if line.startswith("#") and "##" not in line and "#@#" not in line:
            continue
        if "##" in line or "#@#" in line:
            sel = convert_cosmetic(line)
            if sel:
                selectors.append(sel)
            continue
        r = convert_network_filter(line)
        if r:
            key = json.dumps(r, sort_keys=True)
            if key not in seen_rules:
                seen_rules.add(key)
                network_rules.append(r)
    # セレクタ重複除去 (順序保持)
    uniq_sel: list[str] = []
    seen_sel: set[str] = set()
    for s in selectors:
        if s not in seen_sel:
            seen_sel.add(s)
            uniq_sel.append(s)
    return network_rules, uniq_sel


def build_css_rules(selectors: list[str], limit: int) -> list[dict]:
    """汎用cosmeticセレクタをWebKitネイティブの css-display-none ルールに変換。

    JSのMutationObserverよりメモリ/CPUが大幅に軽い (WebKit内部処理のためJSヒープ不使用)。
    triggerは全ページ対象の `.*` 固定。順序依存がないためblock群の後に配置する。
    """
    rules: list[dict] = []
    for sel in selectors[:limit]:
        rules.append({
            "action": {"type": "css-display-none", "selector": sel},
            "trigger": {"url-filter": ".*"},
        })
    return rules


def write_parts(network_rules: list[dict], out_dir: str, max_per_file: int) -> list[str]:
    os.makedirs(out_dir, exist_ok=True)
    # 例外ルール(ignore-previous-rules)は対応するblockより後に置く必要があるためソート。
    # css-display-noneは順序非依存だがblock群の後にまとめる。
    blocks = [r for r in network_rules if r["action"]["type"] == "block"]
    css = [r for r in network_rules if r["action"]["type"] == "css-display-none"]
    ignores = [r for r in network_rules if r["action"]["type"] == "ignore-previous-rules"]
    others = [r for r in network_rules
              if r["action"]["type"] not in ("block", "css-display-none", "ignore-previous-rules")]
    ordered = blocks + css + others + ignores
    paths: list[str] = []
    for i in range(0, len(ordered), max_per_file):
        chunk = ordered[i:i + max_per_file]
        path = os.path.join(out_dir, f"wvb-ubo-part-{len(paths)}.json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(chunk, f, ensure_ascii=False, separators=(",", ":"))
        paths.append(path)
        print(f"wrote {path}: {len(chunk)} rules", file=sys.stderr)
    return paths


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True, help="出力ディレクトリ")
    ap.add_argument("--max-per-file", type=int, default=45000)
    ap.add_argument("--lite", action="store_true",
                    help="軽量版 (EasyList+Peter Lowe+uAssets filtersのみ。約1/3のルール数)")
    ap.add_argument("--max-selectors", type=int, default=3000,
                    help="cosmetic_selectors.jsonに残す上限 (既定3000)")
    ap.add_argument("--emit-css-rules", dest="emit_css", action="store_true", default=True,
                    help="css-display-noneをJSONに埋め込む (既定ON)")
    ap.add_argument("--no-css-rules", dest="emit_css", action="store_false",
                    help="css-display-none埋め込みを無効化")
    ap.add_argument("--max-css-rules", type=int, default=DEFAULT_MAX_CSS_RULES,
                    help=f"JSONに埋め込むCSS上限 (既定{DEFAULT_MAX_CSS_RULES})")
    ap.add_argument("--offline", action="store_true", help="Tools/lists/*.txt から読む")
    ap.add_argument("inputs", nargs="*", help="追加のフィルタファイル")
    args = ap.parse_args()

    lines: list[str] = []
    if args.offline:
        base = os.path.join(os.path.dirname(__file__), "lists")
        if os.path.isdir(base):
            for fn in sorted(os.listdir(base)):
                if fn.endswith(".txt"):
                    with open(os.path.join(base, fn), encoding="utf-8", errors="replace") as f:
                        lines.extend(f.read().splitlines())
        for extra in args.inputs:
            with open(extra, encoding="utf-8", errors="replace") as f:
                lines.extend(f.read().splitlines())
        if not lines:
            print("no offline lists found. put files into Tools/lists/", file=sys.stderr)
            return 2
    else:
        urls = LITE_URLS if args.lite else DEFAULT_URLS
        lines = fetch_all(urls)
        for extra in args.inputs:
            with open(extra, encoding="utf-8", errors="replace") as f:
                lines.extend(f.read().splitlines())

    print(f"total input lines: {len(lines)}", file=sys.stderr)
    network_rules, selectors = convert_lines(lines)
    print(f"network rules: {len(network_rules)}, cosmetic selectors: {len(selectors)}", file=sys.stderr)

    css_count = 0
    if args.emit_css and selectors:
        css_rules = build_css_rules(selectors, args.max_css_rules)
        network_rules = network_rules + css_rules
        css_count = len(css_rules)

    paths = write_parts(network_rules, args.out, args.max_per_file)
    with open(os.path.join(args.out, "cosmetic_selectors.json"), "w", encoding="utf-8") as f:
        json.dump(selectors[:args.max_selectors], f, ensure_ascii=False, indent=1)
    total_bytes = sum(os.path.getsize(p) for p in paths)
    print(f"done: {len(paths)} parts, css rules: {css_count}, "
          f"total JSON: {total_bytes // 1024} KB", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

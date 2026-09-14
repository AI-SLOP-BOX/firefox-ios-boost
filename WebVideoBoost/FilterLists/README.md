# FilterLists (uBOL実リスト内包)

uBlock Origin Lite の既定セット相当の生フィルタをバージョン固定で内包。
ネットワーク取得なしで再現ビルドできる。

## 内容 (`manifest.json` にSHA256・行数・取得元を記録)

| ファイル | 出典 (uBOL既定相当) |
|---|---|
| easylist.txt | EasyList |
| easyprivacy.txt | EasyPrivacy |
| peter-lowe.txt | Peter Lowe's Ad server list |
| uassets-filters.txt | uAssets filters (uBO基本) |
| uassets-badware.txt | uAssets badware |
| uassets-privacy.txt | uAssets privacy |
| uassets-unbreak.txt | uAssets unbreak (誤ブロック解除・例外用) |
| uassets-quick-fixes.txt | uAssets quick-fixes (緊急修正) |

## 更新手順

```bash
cd WebVideoBoost/Tools
./fetch_ubol_lists.sh     # 最新を取得して FilterLists/ + manifest.json を更新
./update_ubol_lists.sh    # 内包rawから Sources/.../AdBlock/Lists/*.json を再生成
```

## uBOLとの対応関係の注意

- uBOLはDNR (declarativeNetRequest) に変換して適用するが、
  iOS WKWebViewにはDNRが無いため、本プロジェクトは生リストから
  WebKit content-blocker JSONに直接変換する (`ublock_to_webkit.py`)。
- DNRでしか表現できない高度記法 (redirect, csp, removeparam, scriptlet等) は
  スキップされる。ネットワーク遮断の核 (`||domain^` 系) は等価。

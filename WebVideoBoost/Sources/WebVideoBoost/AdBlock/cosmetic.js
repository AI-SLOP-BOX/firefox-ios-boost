/* WebVideoBoost / AdBlock cosmetic (省メモリ版)
 * 原則: 非表示化はネイティブの css-display-none ルール (生成JSON内) が担当し、
 * 本JSは「遅延生成された広告枠の掃除」の補助のみ。
 * - <style>1枚を先入れ (CSS側で処理される分はJSヒープを使わない)
 * - MutationObserverは最大SWEEP_BUDGET回で自動切断 (常駐しない)
 * - 非表示タブではsweepをスキップ (バックグラウンド再生中のCPU浪費を防ぐ)
 * Tools/ublock_to_webkit.py が uAssets から selectors.json を吐き、
 * 本スクリプトの __WVB_COSMETIC_SELECTORS に埋め込む運用を想定。
 */
(function () {
  'use strict';
  if (window.__wvbCosmeticInstalled) { return; }
  window.__wvbCosmeticInstalled = true;

  var SELECTORS = (window.__WVB_COSMETIC_SELECTORS || [
    '.ad', '.ads', '.advert', '.advertisement', '.banner-ad', '.ad-banner',
    '.ad-container', '.ads-container', '.sponsored', '.sponsor',
    '[id^="div-gpt-ad"]', '[id^="google_ads"]', '[class*="google-ad"]',
    'ytd-ad-slot-renderer', 'ytd-display-ad-renderer', '.ytd-ad-slot',
    '.video-ads', '.ytp-ad-module', '.ytp-ad-overlay-container'
  ]);

  var SWEEP_BUDGET = 30;      // これ以上変化がなければ監視を切断
  var SWEEP_INTERVAL = 1000;  // 旧300ms→1000ms (CPU/メモリ削減)
  var IDLE_CUTOFF = 5;        // 連続で変化ゼロなら早期切断

  var sweepsLeft = SWEEP_BUDGET;
  var idleStreak = 0;
  var observer = null;
  var joined = null;
  try { joined = SELECTORS.join(','); } catch (e) { return; }

  function ensureStyle() {
    if (document.getElementById('__wvb_cosmetic_style')) { return; }
    var el = document.createElement('style');
    el.id = '__wvb_cosmetic_style';
    try { el.textContent = joined + '{display:none!important;}'; } catch (e) { return; }
    var root = document.head || document.documentElement;
    if (root) { root.appendChild(el); }
  }

  function sweep() {
    // 非表示タブでは何もしない (CSSは効き続ける)
    try { if (document.hidden) { return 0; } } catch (e) {}
    var changed = 0;
    try {
      var nodes = document.querySelectorAll(joined);
      for (var i = 0; i < nodes.length; i++) {
        var n = nodes[i];
        if (n && n.style && n.style.display !== 'none') {
          n.style.setProperty('display', 'none', 'important');
          changed++;
        }
      }
    } catch (e) { return 0; }
    return changed;
  }

  function disconnect() {
    try { if (observer) { observer.disconnect(); } } catch (e) {}
    observer = null;
  }

  function onMutated() {
    if (sweepsLeft <= 0) { disconnect(); return; }
    sweepsLeft--;
    var changed = sweep();
    if (changed === 0) {
      idleStreak++;
      if (idleStreak >= IDLE_CUTOFF) { disconnect(); return; }
    } else {
      idleStreak = 0;
    }
    if (sweepsLeft <= 0) { disconnect(); }
  }

  ensureStyle();
  sweep();
  var throttle = false;
  try {
    observer = new MutationObserver(function () {
      if (throttle || sweepsLeft <= 0) { return; }
      throttle = true;
      setTimeout(function () { throttle = false; onMutated(); }, SWEEP_INTERVAL);
    });
    observer.observe(document.documentElement, { childList: true, subtree: true });
    // 安全弁: 60秒で必ず切断 (ページ滞在が長くても常駐しない)
    setTimeout(disconnect, 60000);
  } catch (e) {}
})();
